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
    $remoteScript = {
        param($ActionParam, $PackageIds, $TimeoutSec)

        $result = @{
            Computer = $env:COMPUTERNAME
            Action = $ActionParam
            Timestamp = (Get-Date -ToString 'o')
            Status = 'Unknown'
            Packages = @()
            Errors = @()
            DurationMs = 0
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Ensure winget COM is available
            $comAvailable = $null -ne (Get-Module -ListAvailable Microsoft.WinGet.Client)
            if (-not $comAvailable) {
                $result.Status = 'Error'
                $result.Errors += "Microsoft.WinGet.Client not available on this machine"
                return ($result | ConvertTo-Json -Depth 5 -Compress)
            }
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop

            switch ($ActionParam) {
                'List' {
                    $pkgs = Get-WinGetPackage
                    $result.Packages = @($pkgs | ForEach-Object {
                        @{ Id = $_.Id; Name = $_.Name; Version = $_.InstalledVersion; Source = $_.Source }
                    })
                    $result.Status = 'Success'
                }
                'State' {
                    $pkgs = Get-WinGetPackage
                    $result.Packages = @($pkgs | ForEach-Object {
                        @{ Id = $_.Id; Name = $_.Name; Version = $_.InstalledVersion; Source = $_.Source; Available = $_.AvailableVersions }
                    })
                    $result.TotalCount = $pkgs.Count
                    $result.UpdatesAvailable = @($pkgs | Where-Object { $_.AvailableVersions -and $_.AvailableVersions[0] -ne $_.InstalledVersion }).Count
                    $result.Status = 'Success'
                }
                'Install' {
                    foreach ($id in $PackageIds) {
                        try {
                            Install-WinGetPackage -Id $id -Mode Silent | Out-Null
                            $result.Packages += @{ Id = $id; Status = 'Installed' }
                        } catch {
                            $result.Packages += @{ Id = $id; Status = 'Failed'; Error = $_.Exception.Message }
                        }
                    }
                    $failedCount = @($result.Packages | Where-Object { $_.Status -eq 'Failed' }).Count
                    $result.Status = if ($failedCount -eq 0) { 'Success' } else { 'PartialFailure' }
                }
                'Uninstall' {
                    foreach ($id in $PackageIds) {
                        try {
                            Uninstall-WinGetPackage -Id $id -Mode Silent | Out-Null
                            $result.Packages += @{ Id = $id; Status = 'Uninstalled' }
                        } catch {
                            $result.Packages += @{ Id = $id; Status = 'Failed'; Error = $_.Exception.Message }
                        }
                    }
                    $failedCount = @($result.Packages | Where-Object { $_.Status -eq 'Failed' }).Count
                    $result.Status = if ($failedCount -eq 0) { 'Success' } else { 'PartialFailure' }
                }
                'Update' {
                    foreach ($id in $PackageIds) {
                        try {
                            Update-WinGetPackage -Id $id -Mode Silent | Out-Null
                            $result.Packages += @{ Id = $id; Status = 'Updated' }
                        } catch {
                            $result.Packages += @{ Id = $id; Status = 'Failed'; Error = $_.Exception.Message }
                        }
                    }
                    $failedCount = @($result.Packages | Where-Object { $_.Status -eq 'Failed' }).Count
                    $result.Status = if ($failedCount -eq 0) { 'Success' } else { 'PartialFailure' }
                }
                'UpdateAll' {
                    $pkgs = Get-WinGetPackage
                    $updatable = $pkgs | Where-Object { $_.AvailableVersions -and $_.AvailableVersions[0] -ne $_.InstalledVersion }
                    foreach ($pkg in $updatable) {
                        try {
                            Update-WinGetPackage -Id $pkg.Id -Mode Silent | Out-Null
                            $result.Packages += @{ Id = $pkg.Id; Status = 'Updated'; Version = $pkg.AvailableVersions[0] }
                        } catch {
                            $result.Packages += @{ Id = $pkg.Id; Status = 'Failed'; Error = $_.Exception.Message }
                        }
                    }
                    $result.UpdatesAvailable = $updatable.Count
                    $failedCount = @($result.Packages | Where-Object { $_.Status -eq 'Failed' }).Count
                    $result.Status = if ($failedCount -eq 0) { 'Success' } else { 'PartialFailure' }
                }
                'Query' {
                    foreach ($id in $PackageIds) {
                        $found = Get-WinGetPackage -Id $id -ErrorAction SilentlyContinue
                        if ($found) {
                            $result.Packages += @{ Id = $id; Installed = $true; Version = $found.InstalledVersion; Name = $found.Name }
                        } else {
                            $result.Packages += @{ Id = $id; Installed = $false }
                        }
                    }
                    $result.Status = 'Success'
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

    $total = $Computers.Count
    $completed = 0
    $batchSize = $ThrottleLimit

    for ($batchStart = 0; $batchStart -lt $total; $batchStart += $batchSize) {
        $batch = $Computers[$batchStart..([Math]::Min($batchStart + $batchSize - 1, $total - 1))]
        $jobs = @()

        foreach ($computer in $batch) {
            $completed++
            Write-Progress -Activity "Fleet: $Action" -Status "[$completed/$total] $computer" -PercentComplete (($completed / $total) * 100)

            if ($UseSSH) {
                $jobs += Invoke-Command -HostName $computer -ScriptBlock $remoteScript -ArgumentList $Action, $PackageId, $TimeoutSeconds @sessionParams -AsJob -ErrorAction SilentlyContinue
            } else {
                $jobs += Invoke-Command -ComputerName $computer -ScriptBlock $remoteScript -ArgumentList $Action, $PackageId, $TimeoutSeconds @sessionParams -AsJob -ErrorAction SilentlyContinue
            }
        }

        # Wait for batch
        $jobs | Wait-Job -Timeout $TimeoutSeconds | Out-Null

        # Collect results
        foreach ($job in $jobs) {
            try {
                $output = Receive-Job $job -ErrorAction Stop
                if ($output) {
                    $parsed = $output | ConvertFrom-Json -AsHashtable
                    $results.Add($parsed)
                } else {
                    $results.Add(@{ Computer = "Unknown"; Status = 'NoResponse'; Errors = @('Job returned no output') })
                }
            } catch {
                $results.Add(@{ Computer = "Unknown"; Status = 'Error'; Errors = @($_.Exception.Message) })
            }
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Progress -Activity "Fleet: $Action" -Completed

    # --- Retry failed ---
    if ($RetryFailed) {
        $failedMachines = $results | Where-Object { $_.Status -in @('Error', 'NoResponse') } | ForEach-Object { $_.Computer }
        if ($failedMachines.Count -gt 0) {
            Write-Host "  Retrying $($failedMachines.Count) failed machines..." -ForegroundColor Yellow
            foreach ($computer in $failedMachines) {
                try {
                    $output = Invoke-Command -ComputerName $computer -ScriptBlock $remoteScript -ArgumentList $Action, $PackageId, $TimeoutSeconds @sessionParams -ErrorAction Stop
                    $parsed = $output | ConvertFrom-Json -AsHashtable
                    # Replace the failed result
                    $idx = $results.FindIndex({ param($r) $r.Computer -eq $computer -and $r.Status -in @('Error', 'NoResponse') })
                    if ($idx -ge 0) { $results[$idx] = $parsed }
                } catch { }
            }
        }
    }

    # --- Aggregate Report ---
    $successCount = ($results | Where-Object { $_.Status -eq 'Success' }).Count
    $partialCount = ($results | Where-Object { $_.Status -eq 'PartialFailure' }).Count
    $failedCount = ($results | Where-Object { $_.Status -in @('Error', 'NoResponse') }).Count

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
            Timestamp = (Get-Date -ToString 'o')
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
