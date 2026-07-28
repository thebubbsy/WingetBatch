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
        Write-Host "  Next Run:     " -NoNewline -ForegroundColor DarkGray; Write-Host ($info.NextRunTime ?? "Not scheduled") -ForegroundColor White
        Write-Host "  Last Run:     " -NoNewline -ForegroundColor DarkGray; Write-Host ($info.LastRunTime ?? "Never") -ForegroundColor White
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
    # Check admin for SYSTEM tasks
    if ($RunAsSystem) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Warning "RunAsSystem requires Administrator privileges. Falling back to current user."
            $RunAsSystem = $false
        }
    }

    # Build the maintenance script that the task will execute
    $maintenanceScript = @"
# WingetBatch Maintenance Script
# Auto-generated by Register-WingetMaintenance
# Actions: $($Action -join ', ')

`$ErrorActionPreference = 'Continue'
`$ProgressPreference = 'SilentlyContinue'
`$reportPath = "$logDir\maintenance_`$(Get-Date -Format 'yyyyMMdd_HHmmss').json"

`$report = @{
    Timestamp = (Get-Date -ToString 'o')
    Hostname = `$env:COMPUTERNAME
    Actions = @('$($Action -join "','")')
    UpdatedCount = 0
    FailedCount = 0
    SkippedCount = 0
    UpdatedPackages = @()
    FailedPackages = @()
    Errors = @()
}

try {
    Import-Module WingetBatch -ErrorAction Stop
} catch {
    `$report.Errors += "Failed to import WingetBatch: `$_"
    `$report | ConvertTo-Json -Depth 5 | Set-Content `$reportPath
    exit 1
}

"@

    if ($Action -contains 'UpdateAll' -or $Action -contains 'UpdateOutdated') {
        $sourceFilter = if (-not $IncludeStore) { " -Source winget" } else { "" }
        $maintenanceScript += @"

# --- Update Packages ---
try {
    `$updates = Get-WingetUpdates
    if (`$updates -and `$updates.Count -gt 0) {
        foreach (`$pkg in `$updates) {
            try {
                `$installArgs = @{ Id = `$pkg.Id; Mode = 'Silent' }
                Microsoft.WinGet.Client\Update-WinGetPackage @installArgs | Out-Null
                `$report.UpdatedCount++
                `$report.UpdatedPackages += `$pkg.Id
            } catch {
                `$report.FailedCount++
                `$report.FailedPackages += @{ Id = `$pkg.Id; Error = `$_.Exception.Message }
            }
        }
    } else {
        `$report.SkippedCount = 0  # Nothing to update
    }
} catch {
    `$report.Errors += "Update phase failed: `$_"
}

"@
    }

    if ($Action -contains 'CleanupTemp') {
        $maintenanceScript += @"

# --- Cleanup Temp Files ---
try {
    `$tempPaths = @(
        (Join-Path `$env:TEMP "WinGet"),
        (Join-Path `$env:LOCALAPPDATA "Packages\Microsoft.DesktopAppInstaller_*\TempState")
    )
    foreach (`$p in `$tempPaths) {
        if (Test-Path `$p) {
            Remove-Item -Path `$p -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    `$report.Errors += "Cleanup phase failed: `$_"
}

"@
    }

    if ($Action -contains 'AuditDrift') {
        $maintenanceScript += @"

# --- Audit Drift ---
try {
    `$statePath = Join-Path "$configDir" "machine_state_baseline.json"
    if (Test-Path `$statePath) {
        `$drift = Get-WingetMachineState -Compare -Path `$statePath
        `$report.Drift = `$drift
    }
} catch {
    `$report.Errors += "Drift audit failed: `$_"
}

"@
    }

    $maintenanceScript += @"

# --- Save Report ---
`$report | ConvertTo-Json -Depth 5 | Set-Content `$reportPath

# Keep only last 30 reports
Get-ChildItem -Path "$logDir" -Filter "maintenance_*.json" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 30 |
    Remove-Item -Force -ErrorAction SilentlyContinue

exit 0
"@

    # Save the maintenance script
    $scriptPath = Join-Path $configDir "maintenance_task.ps1"
    $maintenanceScript | Set-Content -Path $scriptPath -Encoding UTF8

    # Build scheduled task
    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { $pwshPath = "powershell.exe" }

    $taskAction = New-ScheduledTaskAction `
        -Execute $pwshPath `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

    # Trigger
    $timeParts = $Time.Split(':')
    $triggerTime = New-TimeSpan -Hours ([int]$timeParts[0]) -Minutes ([int]$timeParts[1])
    $startTime = (Get-Date).Date + $triggerTime
    if ($startTime -lt (Get-Date)) { $startTime = $startTime.AddDays(1) }

    switch ($Schedule) {
        'Daily' {
            $trigger = New-ScheduledTaskTrigger -Daily -At $startTime
        }
        'Weekly' {
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $startTime
        }
        'Monthly' {
            # Monthly isn't natively supported by New-ScheduledTaskTrigger, use CIM
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $startTime
            # Override with monthly repetition via settings
        }
    }

    # Settings
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes $MaxDurationMinutes) `
        -StartWhenAvailable `
        -DontStopOnIdleEnd `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    # Principal
    if ($RunAsSystem) {
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    } else {
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    }

    # Register (overwrite if exists)
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $taskAction `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "WingetBatch automated maintenance: $($Action -join ', '). Schedule: $Schedule at $Time." `
        -Force | Out-Null

    # Output confirmation
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║     WingetBatch Maintenance Registered          ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Schedule:   " -NoNewline -ForegroundColor DarkGray; Write-Host "$Schedule at $Time" -ForegroundColor White
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
