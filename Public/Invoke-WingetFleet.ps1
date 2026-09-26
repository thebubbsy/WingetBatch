function Invoke-WingetFleet {
    <#
    .SYNOPSIS
        Execute winget operations across multiple remote machines simultaneously.

    .DESCRIPTION
        SCCM-lite for people who hate SCCM. Push package installs, updates, uninstalls,
        and state queries to N machines over WinRM or SSH with parallel execution,
        aggregated reporting, and failure resilience.

        Supports machine lists from files, Active Directory OUs, or inline arrays.
        Results are collected into a structured report with per-machine status.

    .PARAMETER Computers
        Array of computer names/IPs to target.

    .PARAMETER ComputerFile
        Path to a text file with one computer name per line.

    .PARAMETER Action
        Operation to perform: Install, Uninstall, Update, UpdateAll, List, State, Query.

    .PARAMETER PackageId
        Package ID(s) for Install/Uninstall/Query actions.

    .PARAMETER Credential
        PSCredential for remote authentication. Defaults to current user.

    .PARAMETER UseSSH
        Use SSH instead of WinRM for remote connectivity.

    .PARAMETER ThrottleLimit
        Maximum concurrent remote sessions. Default: 10.

    .PARAMETER TimeoutSeconds
        Per-machine operation timeout. Default: 300.

    .PARAMETER ExportReport
        Save aggregated results to a JSON report file.

    .PARAMETER RetryFailed
        Automatically retry failed machines once.

    .EXAMPLE
        Invoke-WingetFleet -Computers "PC01","PC02","PC03" -Action UpdateAll
        Updates all packages on 3 machines in parallel.

    .EXAMPLE
        Invoke-WingetFleet -ComputerFile ".\lab-machines.txt" -Action Install -PackageId "Git.Git","Python.Python.3.12"
        Installs Git and Python on all machines in the file.

    .EXAMPLE
        Invoke-WingetFleet -Computers "Server01" -Action State -Credential (Get-Credential)
        Queries full package state on Server01 with explicit credentials.

    .EXAMPLE
        Invoke-WingetFleet -ComputerFile ".\fleet.txt" -Action List -ExportReport ".\fleet-report.json"
        Lists all packages on every machine and exports a JSON report.

    .NOTES
        Author: Matthew Bubb
        Requires: WinRM (Enable-PSRemoting) or SSH configured on target machines.
        WingetBatch module must be available on remote machines for full functionality.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Inline')]
    param(
        [Parameter(ParameterSetName = 'Inline', Mandatory, Position = 0)]
        [Alias('Machines', 'Hosts')]
        [string[]]$Computers,

        [Parameter(ParameterSetName = 'File', Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ComputerFile,

        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Uninstall', 'Update', 'UpdateAll', 'List', 'State', 'Query')]
        [string]$Action,

        [Parameter()]
        [string[]]$PackageId,

        [Parameter()]
        [PSCredential]$Credential,

        [switch]$UseSSH,

        [ValidateRange(1, 50)]
        [int]$ThrottleLimit = 10,

        [ValidateRange(30, 3600)]
        [int]$TimeoutSeconds = 300,

        [string]$ExportReport,

        [switch]$RetryFailed
    )

    # --- Resolve computer list ---
    if ($ComputerFile) {
        $Computers = Get-Content -Path $ComputerFile | Where-Object { $_.Trim() -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }
    }

    if (-not $Computers -or $Computers.Count -eq 0) {
        Write-Error "No target computers specified."
        return
    }

    # Validate package IDs for actions that need them
    if ($Action -in @('Install', 'Uninstall', 'Update', 'Query') -and -not $PackageId) {
        Write-Error "Action '$Action' requires -PackageId parameter."
        return
    }

    # --- Banner ---
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║           WingetBatch Fleet Operations              ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Targets:   " -NoNewline -ForegroundColor DarkGray; Write-Host "$($Computers.Count) machines" -ForegroundColor White
    Write-Host "  Action:    " -NoNewline -ForegroundColor DarkGray; Write-Host $Action -ForegroundColor Yellow
    if ($PackageId) {
        Write-Host "  Packages:  " -NoNewline -ForegroundColor DarkGray; Write-Host ($PackageId -join ', ') -ForegroundColor White
    }
    Write-Host "  Transport: " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($UseSSH) { "SSH" } else { "WinRM" }) -ForegroundColor White
    Write-Host "  Parallel:  " -NoNewline -ForegroundColor DarkGray; Write-Host "$ThrottleLimit concurrent" -ForegroundColor White
    Write-Host ""

    # --- Build remote script block ---
    # Runs on the target machine (Windows PowerShell 5.1 or 7), so it cannot use
    # WingetBatch's private helpers and must stay 5.1-compatible.
    $remoteScript = {
        param($ActionParam, $PackageIds, $TimeoutSec)

        $result = @{
            Computer   = $env:COMPUTERNAME
            Action     = $ActionParam
            Timestamp  = (Get-Date).ToString('o')
            Status     = 'Unknown'
            Packages   = @()
            Errors     = @()
            DurationMs = 0
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # WinGet cmdlets report installer failures in .Status instead of throwing
        function Invoke-Op {
            param([string]$Verb, [string]$Id, [string]$Source)
            $params = @{ Id = $Id; MatchOption = 'EqualsCaseInsensitive'; Mode = 'Silent'; ErrorAction = 'Stop' }
            if ($Source) { $params['Source'] = $Source }
            try {
                $r = @(& "Microsoft.WinGet.Client\$Verb-WinGetPackage" @params)
                $status = if ($r.Count -gt 0) { [string]$r[-1].Status } else { 'NoResult' }
                $ok = ($status -eq 'Ok') -or ($Verb -eq 'Update' -and $status -eq 'NoApplicableUpgrade')
                return @{ Ok = $ok; Status = $status; Reboot = ($r.Count -gt 0 -and [bool]$r[-1].RebootRequired) }
            }
            catch {
                return @{ Ok = $false; Status = $_.Exception.Message; Reboot = $false }
            }
        }

        try {
            if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client)) {
                $result.Status = 'Error'
                $result.Errors += "Microsoft.WinGet.Client not available on this machine"
                return ($result | ConvertTo-Json -Depth 5 -Compress)
            }
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop

            switch ($ActionParam) {
                'List' {
                    $pkgs = @(Microsoft.WinGet.Client\Get-WinGetPackage)
                    $result.Packages = @($pkgs | ForEach-Object {
                        @{ Id = $_.Id; Name = $_.Name; Version = $_.InstalledVersion; Source = $_.Source }
                    })
                    $result.Status = 'Success'
                }
                'State' {
                    $pkgs = @(Microsoft.WinGet.Client\Get-WinGetPackage)
                    $result.Packages = @($pkgs | ForEach-Object {
                        @{ Id = $_.Id; Name = $_.Name; Version = $_.InstalledVersion; Source = $_.Source; Available = @($_.AvailableVersions)[0]; UpdateAvailable = [bool]$_.IsUpdateAvailable }
                    })
                    $result.TotalCount = $pkgs.Count
                    $result.UpdatesAvailable = @($pkgs | Where-Object { $_.IsUpdateAvailable }).Count
                    $result.Status = 'Success'
                }
                { $_ -in 'Install', 'Uninstall', 'Update' } {
                    $pastTense = @{ Install = 'Installed'; Uninstall = 'Uninstalled'; Update = 'Updated' }[$ActionParam]
                    foreach ($id in $PackageIds) {
                        $op = Invoke-Op -Verb $ActionParam -Id $id
                        if ($op.Ok) { $result.Packages += @{ Id = $id; Status = $pastTense; RebootRequired = $op.Reboot } }
                        else { $result.Packages += @{ Id = $id; Status = 'Failed'; Error = $op.Status } }
                    }
                }
                'UpdateAll' {
                    $updatable = @(Microsoft.WinGet.Client\Get-WinGetPackage | Where-Object { $_.IsUpdateAvailable })
                    foreach ($pkg in $updatable) {
                        $op = Invoke-Op -Verb 'Update' -Id $pkg.Id -Source $pkg.Source
                        if ($op.Ok) { $result.Packages += @{ Id = $pkg.Id; Status = 'Updated'; Version = @($pkg.AvailableVersions)[0]; RebootRequired = $op.Reboot } }
                        else { $result.Packages += @{ Id = $pkg.Id; Status = 'Failed'; Error = $op.Status } }
                    }
                    $result.UpdatesAvailable = $updatable.Count
                }
                'Query' {
                    foreach ($id in $PackageIds) {
                        $found = Microsoft.WinGet.Client\Get-WinGetPackage -Id $id -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($found) {
                            $result.Packages += @{ Id = $id; Installed = $true; Version = $found.InstalledVersion; Name = $found.Name; UpdateAvailable = [bool]$found.IsUpdateAvailable }
                        } else {
                            $result.Packages += @{ Id = $id; Installed = $false }
                        }
                    }
                    $result.Status = 'Success'
                }
            }

            if ($ActionParam -in 'Install', 'Uninstall', 'Update', 'UpdateAll') {
                $failedCount = @($result.Packages | Where-Object { $_.Status -eq 'Failed' }).Count
                $result.Status = if ($failedCount -eq 0) { 'Success' } elseif ($failedCount -lt $result.Packages.Count) { 'PartialFailure' } else { 'Error' }
                if ($failedCount -gt 0) {
                    $result.Errors += @($result.Packages | Where-Object { $_.Status -eq 'Failed' } | ForEach-Object { "$($_.Id): $($_.Error)" })
                }
            }
        } catch {
            $result.Status = 'Error'
            $result.Errors += $_.Exception.Message
        }

        $sw.Stop()
        $result.DurationMs = $sw.ElapsedMilliseconds
        return ($result | ConvertTo-Json -Depth 5 -Compress)
    }

    # --- Execute across fleet ---
    $results = [System.Collections.Generic.List[hashtable]]::new()
    $sessionParams = @{}
    if ($Credential) { $sessionParams['Credential'] = $Credential }

    # One place that knows how to reach a machine (WinRM or SSH)
    $invokeRemote = {
        param([string]$Computer, [switch]$AsJob)
        $target = if ($UseSSH) { @{ HostName = $Computer } } else { @{ ComputerName = $Computer } }
        Invoke-Command @target @sessionParams -ScriptBlock $remoteScript -ArgumentList $Action, $PackageId, $TimeoutSeconds -AsJob:$AsJob -ErrorAction Stop
    }

    $total = $Computers.Count
    $completed = 0

    for ($batchStart = 0; $batchStart -lt $total; $batchStart += $ThrottleLimit) {
        $batch = $Computers[$batchStart..([Math]::Min($batchStart + $ThrottleLimit - 1, $total - 1))]
        $jobMap = @{}

        foreach ($computer in $batch) {
            $completed++
            Write-Progress -Activity "Fleet: $Action" -Status "[$completed/$total] $computer" -PercentComplete (($completed / $total) * 100)
            try {
                $job = & $invokeRemote -Computer $computer -AsJob
                $jobMap[$job.Id] = @{ Job = $job; Computer = $computer }
            }
            catch {
                $results.Add(@{ Computer = $computer; Status = 'Error'; Errors = @($_.Exception.Message) })
            }
        }

        # Wait for batch
        $batchJobs = @($jobMap.Values | ForEach-Object { $_.Job })
        if ($batchJobs.Count -gt 0) {
            $batchJobs | Wait-Job -Timeout $TimeoutSeconds | Out-Null
        }

        # Collect results
        foreach ($entry in $jobMap.Values) {
            $job = $entry.Job
            $computer = $entry.Computer
            try {
                if ($job.State -eq 'Running') {
                    Stop-Job $job -ErrorAction SilentlyContinue
                    $results.Add(@{ Computer = $computer; Status = 'Timeout'; Errors = @("No response within $TimeoutSeconds seconds") })
                    continue
                }
                $output = Receive-Job $job -ErrorAction Stop
                if ($output) {
                    $parsed = @($output)[-1] | ConvertFrom-Json -AsHashtable
                    # Report under the name we targeted (the remote COMPUTERNAME may differ, e.g. IPs)
                    $parsed['Computer'] = $computer
                    $results.Add($parsed)
                } else {
                    $results.Add(@{ Computer = $computer; Status = 'NoResponse'; Errors = @('Job returned no output') })
                }
            } catch {
                $results.Add(@{ Computer = $computer; Status = 'Error'; Errors = @($_.Exception.Message) })
            }
            finally {
                Remove-Job $job -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Progress -Activity "Fleet: $Action" -Completed

    # --- Retry failed ---
    if ($RetryFailed) {
        $failedMachines = @($results | Where-Object { $_.Status -in @('Error', 'NoResponse', 'Timeout') } | ForEach-Object { $_.Computer })
        if ($failedMachines.Count -gt 0) {
            Write-Host "  Retrying $($failedMachines.Count) failed machines..." -ForegroundColor Yellow
            foreach ($computer in $failedMachines) {
                $idx = $results.FindIndex([Predicate[hashtable]] { param($r) $r.Computer -eq $computer })
                try {
                    $output = & $invokeRemote -Computer $computer
                    $parsed = @($output)[-1] | ConvertFrom-Json -AsHashtable
                    $parsed['Computer'] = $computer
                    if ($idx -ge 0) { $results[$idx] = $parsed }
                } catch {
                    if ($idx -ge 0) { $results[$idx]['Errors'] = @($results[$idx]['Errors']) + "Retry failed: $($_.Exception.Message)" }
                }
            }
        }
    }

    # --- Aggregate Report ---
    $successCount = @($results | Where-Object { $_.Status -eq 'Success' }).Count
    $partialCount = @($results | Where-Object { $_.Status -eq 'PartialFailure' }).Count
    $failedCount = @($results | Where-Object { $_.Status -in @('Error', 'NoResponse', 'Timeout') }).Count

    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "  │              Fleet Operation Results                 │" -ForegroundColor White
    Write-Host "  ├─────────────────────────────────────────────────────┤" -ForegroundColor White
    Write-Host "  │  " -NoNewline -ForegroundColor White
    Write-Host "Success: $successCount" -NoNewline -ForegroundColor Green
    Write-Host "  |  " -NoNewline -ForegroundColor White
    Write-Host "Partial: $partialCount" -NoNewline -ForegroundColor Yellow
    Write-Host "  |  " -NoNewline -ForegroundColor White
    Write-Host "Failed: $failedCount" -NoNewline -ForegroundColor Red
    Write-Host "  │" -ForegroundColor White
    Write-Host "  └─────────────────────────────────────────────────────┘" -ForegroundColor White
    Write-Host ""

    # Per-machine summary
    foreach ($r in ($results | Sort-Object { $_.Computer })) {
        $icon = switch ($r.Status) {
            'Success' { '✓' }
            'PartialFailure' { '◐' }
            default { '✗' }
        }
        $color = switch ($r.Status) {
            'Success' { 'Green' }
            'PartialFailure' { 'Yellow' }
            default { 'Red' }
        }
        $duration = if ($r.DurationMs) { " ($([Math]::Round($r.DurationMs / 1000, 1))s)" } else { "" }
        Write-Host "  $icon " -NoNewline -ForegroundColor $color
        Write-Host "$($r.Computer)" -NoNewline -ForegroundColor White
        Write-Host " — $($r.Status)$duration" -ForegroundColor $color

        if ($r.Errors -and $r.Errors.Count -gt 0) {
            foreach ($err in $r.Errors | Select-Object -First 2) {
                Write-Host "      $err" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""

    # --- Export ---
    if ($ExportReport) {
        $report = @{
            Timestamp = (Get-Date).ToString('o')
            Action = $Action
            PackageIds = $PackageId
            TotalMachines = $total
            Success = $successCount
            PartialFailure = $partialCount
            Failed = $failedCount
            Results = $results
        }
        $report | ConvertTo-Json -Depth 10 | Set-Content -Path $ExportReport -Encoding UTF8
        Write-Host "  Report saved: $ExportReport" -ForegroundColor Green
        Write-Host ""
    }

    # Return structured results for pipeline
    $results | ForEach-Object { [PSCustomObject]$_ }
}
