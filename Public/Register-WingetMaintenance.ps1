function Register-WingetMaintenance {
    <#
    .SYNOPSIS
        Register a scheduled maintenance task for automatic winget package management.

    .DESCRIPTION
        Creates a Windows Scheduled Task that automatically updates, cleans up, and/or
        audits installed packages on a configurable schedule. Supports daily, weekly,
        and monthly recurrence with customizable actions and notification preferences.

        The maintenance task runs as SYSTEM by default (for machine-wide updates) or
        as the current user (for per-user packages). Results are logged to a JSON
        report in the WingetBatch config directory.

    .PARAMETER Schedule
        Recurrence pattern: Daily, Weekly, or Monthly. Default: Weekly.

    .PARAMETER Time
        Time of day to run maintenance (24h format). Default: 03:00.

    .PARAMETER DayOfWeek
        For Weekly schedule: which day(s) to run. Default: Sunday.

    .PARAMETER DayOfMonth
        For Monthly schedule: which day of the month. Default: 1.

    .PARAMETER Action
        What maintenance actions to perform. Multiple allowed.
        Options: UpdateAll, UpdateOutdated, CleanupTemp, AuditDrift, NotifyOnly.
        Default: UpdateAll, CleanupTemp.

    .PARAMETER TaskName
        Custom name for the scheduled task. Default: "WingetBatch Maintenance".

    .PARAMETER RunAsSystem
        Run the task as SYSTEM (elevated, machine-wide). Default: true.
        Set -RunAsSystem:$false to run as current user.

    .PARAMETER IncludeStore
        Include Microsoft Store packages in updates. Default: false.

    .PARAMETER MaxDurationMinutes
        Maximum execution time before the task is killed. Default: 120.

    .PARAMETER Unregister
        Remove the scheduled maintenance task.

    .PARAMETER Status
        Show the current maintenance task configuration and last run result.

    .PARAMETER RunNow
        Trigger the maintenance task immediately (for testing).

    .EXAMPLE
        Register-WingetMaintenance
        Registers weekly Sunday 3AM maintenance with update-all and temp cleanup.

    .EXAMPLE
        Register-WingetMaintenance -Schedule Daily -Time 02:00 -Action UpdateAll, AuditDrift
        Daily 2AM maintenance that updates all packages and audits drift.

    .EXAMPLE
        Register-WingetMaintenance -Status
        Shows current task configuration, next run time, and last result.

    .EXAMPLE
        Register-WingetMaintenance -Unregister
        Removes the scheduled maintenance task.

    .NOTES
        Author: Matthew Bubb
        Requires: Run as Administrator for -RunAsSystem (default).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Register')]
    param(
        [Parameter(ParameterSetName = 'Register')]
        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$Schedule = 'Weekly',

        [Parameter(ParameterSetName = 'Register')]
        [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')]
        [string]$Time = '03:00',

        [Parameter(ParameterSetName = 'Register')]
        [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string[]]$DayOfWeek = @('Sunday'),

        [Parameter(ParameterSetName = 'Register')]
        [ValidateRange(1, 31)]
        [int]$DayOfMonth = 1,

        [Parameter(ParameterSetName = 'Register')]
        [ValidateSet('UpdateAll', 'UpdateOutdated', 'CleanupTemp', 'AuditDrift', 'NotifyOnly')]
        [string[]]$Action = @('UpdateAll', 'CleanupTemp'),

        [Parameter(ParameterSetName = 'Register')]
        [string]$TaskName = 'WingetBatch Maintenance',

        [Parameter(ParameterSetName = 'Register')]
        [bool]$RunAsSystem = $true,

        [Parameter(ParameterSetName = 'Register')]
        [switch]$IncludeStore,

        [Parameter(ParameterSetName = 'Register')]
        [ValidateRange(10, 480)]
        [int]$MaxDurationMinutes = 120,

        [Parameter(ParameterSetName = 'Unregister', Mandatory)]
        [switch]$Unregister,

        [Parameter(ParameterSetName = 'Status', Mandatory)]
        [switch]$Status,

        [Parameter(ParameterSetName = 'Register')]
        [switch]$RunNow
    )

    # --- Config directory ---
    $configDir = Get-WingetBatchConfigDir
    $logDir = Join-Path $configDir "maintenance"
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # --- STATUS ---
    if ($Status) {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $existingTask) {
            Write-Host "`n  No maintenance task registered." -ForegroundColor Yellow
            Write-Host "  Run 'Register-WingetMaintenance' to create one.`n" -ForegroundColor DarkGray
            return
        }

        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        $lastResult = if ($info.LastTaskResult -eq 0) { "Success" } 
                      elseif ($info.LastTaskResult -eq 267011) { "Never run" }
                      else { "Exit code: $($info.LastTaskResult)" }

        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "  ║       WingetBatch Maintenance Status            ║" -ForegroundColor Cyan
        Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Task Name:    " -NoNewline -ForegroundColor DarkGray; Write-Host $TaskName -ForegroundColor White
        Write-Host "  State:        " -NoNewline -ForegroundColor DarkGray; Write-Host $existingTask.State -ForegroundColor $(if ($existingTask.State -eq 'Ready') { 'Green' } else { 'Yellow' })
        Write-Host "  Next Run:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($info.NextRunTime) { $info.NextRunTime } else { 'Not scheduled' }) -ForegroundColor White
        Write-Host "  Last Run:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($info.LastRunTime -and $info.LastRunTime.Year -gt 2000) { $info.LastRunTime } else { 'Never' }) -ForegroundColor White
        Write-Host "  Last Result:  " -NoNewline -ForegroundColor DarkGray; Write-Host $lastResult -ForegroundColor $(if ($lastResult -eq 'Success' -or $lastResult -eq 'Never run') { 'Green' } else { 'Red' })
        Write-Host ""

        # Show last report if available
        $lastReport = Get-ChildItem -Path $logDir -Filter "maintenance_*.json" -ErrorAction SilentlyContinue | 
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($lastReport) {
            $report = Get-Content $lastReport.FullName -Raw | ConvertFrom-Json
            Write-Host "  Last Report:  " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($report.UpdatedCount) updated, $($report.FailedCount) failed, $($report.SkippedCount) skipped" -ForegroundColor White
            Write-Host "  Report File:  " -NoNewline -ForegroundColor DarkGray
            Write-Host $lastReport.FullName -ForegroundColor DarkGray
        }
        Write-Host ""
        return
    }

    # --- UNREGISTER ---
    if ($Unregister) {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $existingTask) {
            Write-Host "  Task '$TaskName' not found. Nothing to remove." -ForegroundColor Yellow
            return
        }
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  ✓ Maintenance task '$TaskName' removed." -ForegroundColor Green
        return
    }

    # --- REGISTER ---
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($RunAsSystem -and -not $isAdmin) {
        Write-Warning "RunAsSystem requires Administrator privileges. Falling back to current user."
        $RunAsSystem = $false
    }

    if ($Action -contains 'AuditDrift' -and -not (Test-Path (Join-Path $configDir "machine_state_baseline.json"))) {
        Write-Warning "AuditDrift needs a baseline. Create one with: Get-WingetMachineState -Export -Path '$(Join-Path $configDir "machine_state_baseline.json")'"
    }

    # Values baked into the generated script. Single quotes are doubled so paths
    # containing apostrophes cannot break out of the string literals.
    $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
    $modulePath = Join-Path $PSScriptRoot "..\WingetBatch.psd1"
    if (-not (Test-Path $modulePath)) { $modulePath = Join-Path (Get-Module WingetBatch).ModuleBase "WingetBatch.psd1" }
    $modulePath = [System.IO.Path]::GetFullPath($modulePath)
    $actionList = ($Action | ForEach-Object { & $q $_ }) -join ', '
    $doUpdate = ($Action -contains 'UpdateAll' -or $Action -contains 'UpdateOutdated')
    $doCheck = $doUpdate -or ($Action -contains 'NotifyOnly')

    $maintenanceScript = @"
# WingetBatch Maintenance Script
# Auto-generated by Register-WingetMaintenance on $((Get-Date).ToString('yyyy-MM-dd HH:mm'))
# Actions: $($Action -join ', ')

`$ErrorActionPreference = 'Continue'
`$ProgressPreference = 'SilentlyContinue'
`$logDir = $(& $q $logDir)
`$configDir = $(& $q $configDir)
`$modulePath = $(& $q $modulePath)
`$reportPath = Join-Path `$logDir "maintenance_`$(Get-Date -Format 'yyyyMMdd_HHmmss').json"

"@

    if ($Schedule -eq 'Monthly') {
        # Task Scheduler cmdlets have no monthly trigger: the task runs daily and exits
        # unless today is the chosen day (or the month's last day for days 29-31).
        $maintenanceScript += @"
# --- Monthly gate ---
`$today = Get-Date
`$runDay = [Math]::Min($DayOfMonth, [DateTime]::DaysInMonth(`$today.Year, `$today.Month))
if (`$today.Day -ne `$runDay) { exit 0 }

"@
    }

    $maintenanceScript += @"
`$report = [ordered]@{
    Timestamp        = (Get-Date).ToString('o')
    Hostname         = `$env:COMPUTERNAME
    Actions          = @($actionList)
    UpdatesAvailable = 0
    UpdatedCount     = 0
    FailedCount      = 0
    SkippedCount     = 0
    UpdatedPackages  = @()
    FailedPackages   = @()
    Errors           = @()
}

function Save-Report {
    `$report | ConvertTo-Json -Depth 6 | Set-Content -Path `$reportPath -Encoding UTF8
}

try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
} catch {
    `$report.Errors += "Failed to import Microsoft.WinGet.Client: `$_"
    Save-Report
    exit 1
}

"@

    if ($doCheck) {
        $storeFilter = if ($IncludeStore) { '' } else { " | Where-Object { `$_.Source -ne 'msstore' }" }
        $maintenanceScript += @"
# --- Check for updates ---
try {
    `$updates = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction Stop | Where-Object { `$_.IsUpdateAvailable }$storeFilter)
    `$report.UpdatesAvailable = `$updates.Count
} catch {
    `$updates = @()
    `$report.Errors += "Update check failed: `$_"
}

"@
    }

    if ($doUpdate) {
        $maintenanceScript += @"
# --- Update packages (result status is checked; the cmdlet does not throw on installer failure) ---
foreach (`$pkg in `$updates) {
    try {
        `$params = @{ Id = `$pkg.Id; MatchOption = 'EqualsCaseInsensitive'; Mode = 'Silent'; ErrorAction = 'Stop' }
        if (`$pkg.Source) { `$params['Source'] = `$pkg.Source }
        `$r = @(Microsoft.WinGet.Client\Update-WinGetPackage @params)[-1]
        if (`$r -and [string]`$r.Status -eq 'Ok') {
            `$report.UpdatedCount++
            `$report.UpdatedPackages += `$pkg.Id
        } else {
            `$report.FailedCount++
            `$report.FailedPackages += @{ Id = `$pkg.Id; Error = [string]`$r.Status }
        }
    } catch {
        `$report.FailedCount++
        `$report.FailedPackages += @{ Id = `$pkg.Id; Error = `$_.Exception.Message }
    }
}

"@
    }
    elseif ($doCheck) {
        $maintenanceScript += @"
# NotifyOnly: report what is pending without changing anything
`$report.SkippedCount = `$updates.Count

"@
    }

    if ($Action -contains 'CleanupTemp') {
        $maintenanceScript += @"
# --- Cleanup Temp Files ---
try {
    `$tempPaths = @(
        (Join-Path `$env:TEMP "WinGet"),
        (Join-Path `$env:LOCALAPPDATA "Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\TempState")
    )
    foreach (`$p in `$tempPaths) {
        if (Test-Path `$p) {
            Get-ChildItem -Path `$p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    `$report.Errors += "Cleanup phase failed: `$_"
}

"@
    }

    $maintenanceScript += @"
# WingetBatch is only needed for drift audits and webhooks
`$wingetBatchLoaded = `$false
if ($(if ($Action -contains 'AuditDrift') { '$true' } else { '$false' }) -or (Test-Path (Join-Path `$configDir 'config.json'))) {
    try { Import-Module WingetBatch -ErrorAction Stop; `$wingetBatchLoaded = `$true }
    catch {
        try { Import-Module `$modulePath -ErrorAction Stop; `$wingetBatchLoaded = `$true }
        catch { `$report.Errors += "Could not load WingetBatch: `$_" }
    }
}

"@

    if ($Action -contains 'AuditDrift') {
        $maintenanceScript += @"
# --- Audit Drift ---
try {
    `$statePath = Join-Path `$configDir "machine_state_baseline.json"
    if (-not (Test-Path `$statePath)) {
        `$report.Errors += "Drift audit skipped: no baseline at `$statePath"
    } elseif (`$wingetBatchLoaded) {
        `$drift = Get-WingetMachineState -Compare -Path `$statePath 6>`$null
        `$report.Drift = [ordered]@{
            IsCompliant = `$drift.IsCompliant
            Missing     = @(`$drift.Missing)
            Outdated    = @(`$drift.Outdated | ForEach-Object { `$_.Id })
            Extraneous  = @(`$drift.Extraneous)
        }
    }
} catch {
    `$report.Errors += "Drift audit failed: `$_"
}

"@
    }

    $maintenanceScript += @"
# --- Webhook notifications (webhooks saved with Send-WingetWebhook -SaveConfig) ---
if (`$wingetBatchLoaded) {
    try {
        `$cfg = Get-Content (Join-Path `$configDir 'config.json') -Raw | ConvertFrom-Json
        foreach (`$platform in 'Discord', 'Slack', 'Teams') {
            `$url = `$cfg."webhook_`$(`$platform.ToLower())"
            if (-not `$url) { continue }
            `$msg = "`$(`$report.UpdatesAvailable) update(s) available, `$(`$report.UpdatedCount) updated, `$(`$report.FailedCount) failed."
            if (`$report.Drift -and -not `$report.Drift.IsCompliant) { `$msg += " Drift detected against baseline." }
            Send-WingetWebhook -Platform `$platform -WebhookUrl `$url -Event MaintenanceComplete -Message `$msg 6>`$null | Out-Null
        }
    } catch {
        `$report.Errors += "Webhook notification failed: `$_"
    }
}

# --- Save Report ---
Save-Report

# Keep only last 30 reports
Get-ChildItem -Path `$logDir -Filter "maintenance_*.json" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 30 |
    Remove-Item -Force -ErrorAction SilentlyContinue

exit `$(if (`$report.FailedCount -gt 0 -or `$report.Errors.Count -gt 0) { 1 } else { 0 })
"@

    # Save the maintenance script
    $scriptPath = Join-Path $configDir "maintenance_task.ps1"
    $maintenanceScript | Set-Content -Path $scriptPath -Encoding UTF8

    # Build scheduled task
    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) {
        Write-Error "pwsh.exe (PowerShell 7) was not found in PATH. The maintenance task requires PowerShell 7."
        return
    }

    $taskAction = New-ScheduledTaskAction `
        -Execute $pwshPath `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

    # Trigger
    $timeParts = $Time.Split(':')
    $triggerTime = New-TimeSpan -Hours ([int]$timeParts[0]) -Minutes ([int]$timeParts[1])
    $startTime = (Get-Date).Date + $triggerTime
    if ($startTime -lt (Get-Date)) { $startTime = $startTime.AddDays(1) }

    switch ($Schedule) {
        'Daily'   { $trigger = New-ScheduledTaskTrigger -Daily -At $startTime }
        'Weekly'  { $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $startTime }
        'Monthly' { $trigger = New-ScheduledTaskTrigger -Daily -At $startTime }  # gated to $DayOfMonth inside the script
    }

    # Settings
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes $MaxDurationMinutes) `
        -StartWhenAvailable `
        -DontStopOnIdleEnd `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    # Principal (Highest only when we can actually grant it)
    if ($RunAsSystem) {
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    } else {
        $runLevel = if ($isAdmin) { 'Highest' } else { 'Limited' }
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel $runLevel
    }

    # Register (overwrite if exists)
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $scheduleText = switch ($Schedule) {
        'Daily'   { "Daily at $Time" }
        'Weekly'  { "Weekly ($($DayOfWeek -join ', ')) at $Time" }
        'Monthly' { "Monthly on day $DayOfMonth at $Time" }
    }

    try {
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $taskAction `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description "WingetBatch automated maintenance: $($Action -join ', '). $scheduleText." `
            -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "Failed to register scheduled task: $($_.Exception.Message)"
        return
    }


    # Output confirmation
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║     WingetBatch Maintenance Registered          ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Schedule:   " -NoNewline -ForegroundColor DarkGray; Write-Host $scheduleText -ForegroundColor White
    Write-Host "  Actions:    " -NoNewline -ForegroundColor DarkGray; Write-Host ($Action -join ', ') -ForegroundColor White
    Write-Host "  Run As:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($RunAsSystem) { "SYSTEM" } else { $env:USERNAME }) -ForegroundColor White
    Write-Host "  Store Pkgs: " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($IncludeStore) { "Included" } else { "Excluded" }) -ForegroundColor White
    Write-Host "  Timeout:    " -NoNewline -ForegroundColor DarkGray; Write-Host "${MaxDurationMinutes}m" -ForegroundColor White
    Write-Host "  Script:     " -NoNewline -ForegroundColor DarkGray; Write-Host $scriptPath -ForegroundColor DarkGray
    Write-Host "  Reports:    " -NoNewline -ForegroundColor DarkGray; Write-Host $logDir -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor DarkGray
    Write-Host "    Register-WingetMaintenance -Status    # Check status" -ForegroundColor DarkGray
    Write-Host "    Register-WingetMaintenance -RunNow    # Test run" -ForegroundColor DarkGray
    Write-Host "    Register-WingetMaintenance -Unregister # Remove" -ForegroundColor DarkGray
    Write-Host ""

    # Optional: run immediately
    if ($RunNow) {
        Write-Host "  Triggering maintenance now..." -ForegroundColor Cyan
        Start-ScheduledTask -TaskName $TaskName
        Start-Sleep -Seconds 2
        $taskState = (Get-ScheduledTask -TaskName $TaskName).State
        Write-Host "  Task state: $taskState" -ForegroundColor $(if ($taskState -eq 'Running') { 'Green' } else { 'Yellow' })
    }
}
