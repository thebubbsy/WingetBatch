function Get-WingetHistory {
    <#
    .SYNOPSIS
        Display package installation history as a timeline.

    .DESCRIPTION
        Reads installation history from the Windows Registry and winget logs to
        display a chronological timeline of package installations, updates, and
        removals on the system.

        Supports filtering by date range, searching by package name, and exporting
        to HTML for audit purposes.

    .PARAMETER Days
        Show history from the last N days. Default: 30.

    .PARAMETER All
        Show all available history (no date filter).

    .PARAMETER Search
        Filter history entries by package name or ID.

    .PARAMETER ExportHtml
        Generate an HTML timeline report.

    .PARAMETER ExportJson
        Output raw history data as JSON for programmatic use.

    .EXAMPLE
        Get-WingetHistory
        Shows installations from the last 30 days.

    .EXAMPLE
        Get-WingetHistory -Days 7
        Shows what was installed in the last week.

    .EXAMPLE
        Get-WingetHistory -Search "python"
        Shows all Python-related installation events.

    .EXAMPLE
        Get-WingetHistory -All -ExportHtml
        Full history exported as an HTML report.

    .LINK
        https://github.com/thebubbsy/WingetBatch
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$Days = 30,

        [Parameter()]
        [switch]$All,

        [Parameter()]
        [string]$Search,

        [Parameter()]
        [switch]$ExportHtml,

        [Parameter()]
        [switch]$ExportJson
    )

    begin {
        if (-not (Get-Module -Name PwshSpectreConsole)) {
            if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
                Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
            }
        }
    }

    process {
        Write-Host ""
        Write-Host "  Scanning installation history..." -ForegroundColor Cyan

        $history = [System.Collections.Generic.List[PSCustomObject]]::new()
        $cutoffDate = if ($All) { [DateTime]::MinValue } else { (Get-Date).AddDays(-$Days) }

        # Source 1: Windows Registry (Uninstall keys)
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        foreach ($regPath in $regPaths) {
            $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            foreach ($entry in $entries) {
                if (-not $entry.DisplayName) { continue }
                if (-not $entry.InstallDate) { continue }

                try {
                    $installDate = [DateTime]::ParseExact($entry.InstallDate, 'yyyyMMdd', $null)
                } catch {
                    try { $installDate = [DateTime]::Parse($entry.InstallDate) }
                    catch { continue }
                }

                if ($installDate -lt $cutoffDate) { continue }

                # Apply search filter
                if ($Search) {
                    $matchText = "$($entry.DisplayName) $($entry.Publisher) $($entry.PSChildName)"
                    if ($matchText -notlike "*$Search*") { continue }
                }

                $scope = if ($regPath -like 'HKCU:*') { 'User' } else { 'Machine' }

                $history.Add([PSCustomObject]@{
                    Date        = $installDate
                    Action      = 'Installed'
                    Name        = $entry.DisplayName
                    Version     = if ($entry.DisplayVersion) { $entry.DisplayVersion } else { '' }
                    Publisher   = if ($entry.Publisher) { $entry.Publisher } else { '' }
                    Scope       = $scope
                    Source      = 'Registry'
                    SizeMB      = if ($entry.EstimatedSize) { [Math]::Round($entry.EstimatedSize / 1024, 1) } else { $null }
                })
            }
        }

        # Source 2: Winget log files (if available)
        $wingetLogDir = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir"
        if (Test-Path $wingetLogDir) {
            $logFiles = Get-ChildItem -Path $wingetLogDir -Filter "*.log" -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $cutoffDate } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 20

            foreach ($logFile in $logFiles) {
                try {
                    $logContent = Get-Content $logFile.FullName -Tail 100 -ErrorAction SilentlyContinue
                    foreach ($line in $logContent) {
                        # Parse winget log entries for install/update operations
                        if ($line -match '(\d{4}-\d{2}-\d{2})\s+.*(?:Installing|Updating|Uninstalling)\s+.*?(\S+\.\S+)') {
                            $logDate = [DateTime]::Parse($Matches[1])
                            if ($logDate -lt $cutoffDate) { continue }

                            $action = if ($line -match 'Installing') { 'Installed' }
                                      elseif ($line -match 'Updating') { 'Updated' }
                                      elseif ($line -match 'Uninstalling') { 'Removed' }
                                      else { 'Unknown' }

                            $pkgId = $Matches[2]
                            if ($Search -and $pkgId -notlike "*$Search*") { continue }

                            $history.Add([PSCustomObject]@{
                                Date      = $logDate
                                Action    = $action
                                Name      = $pkgId
                                Version   = ''
                                Publisher = ''
                                Scope     = ''
                                Source    = 'WingetLog'
                                SizeMB    = $null
                            })
                        }
                    }
                } catch {}
            }
        }

        # Sort by date descending
        $history = [System.Collections.Generic.List[PSCustomObject]]($history | Sort-Object Date -Descending)

        if ($history.Count -eq 0) {
            Write-Host "  No installation history found" -ForegroundColor Yellow -NoNewline
            if (-not $All) { Write-Host " in the last $Days days" -ForegroundColor Yellow -NoNewline }
            Write-Host "." -ForegroundColor Yellow
            Write-Host ""
            return
        }

        # JSON export
        if ($ExportJson) {
            $history | ConvertTo-Json -Depth 5
            return
        }

        # Display timeline
        $dateRange = if ($All) { "all time" } else { "last $Days days" }
        Write-Host "  Found " -ForegroundColor White -NoNewline
        Write-Host "$($history.Count)" -ForegroundColor Green -NoNewline
        Write-Host " events ($dateRange)" -ForegroundColor White
        Write-Host ""

        # Group by date for timeline display
        $grouped = $history | Group-Object { $_.Date.ToString('yyyy-MM-dd') } | Sort-Object Name -Descending

        foreach ($dayGroup in $grouped) {
            $dateStr = $dayGroup.Name
            $dayOfWeek = ([DateTime]::Parse($dateStr)).DayOfWeek

            Write-Host "  $dateStr" -ForegroundColor Cyan -NoNewline
            Write-Host " ($dayOfWeek)" -ForegroundColor DarkGray
            Write-Host "  $('─' * 50)" -ForegroundColor DarkGray

            foreach ($event in $dayGroup.Group) {
                $actionColor = switch ($event.Action) {
                    'Installed' { 'Green' }
                    'Updated' { 'Yellow' }
                    'Removed' { 'Red' }
                    default { 'Gray' }
                }
                $actionIcon = switch ($event.Action) {
                    'Installed' { '+' }
                    'Updated' { '~' }
                    'Removed' { '-' }
                    default { '?' }
                }

                Write-Host "    [$actionIcon] " -ForegroundColor $actionColor -NoNewline
                Write-Host $event.Name -ForegroundColor White -NoNewline

                if ($event.Version) {
                    Write-Host " v$($event.Version)" -ForegroundColor Green -NoNewline
                }
                if ($event.Publisher) {
                    Write-Host " ($($event.Publisher))" -ForegroundColor DarkGray -NoNewline
                }
                if ($event.SizeMB) {
                    Write-Host " [$($event.SizeMB) MB]" -ForegroundColor DarkGray -NoNewline
                }
                Write-Host ""
            }
            Write-Host ""
        }

        # Summary stats
        $installCount = ($history | Where-Object { $_.Action -eq 'Installed' }).Count
        $updateCount = ($history | Where-Object { $_.Action -eq 'Updated' }).Count
        $removeCount = ($history | Where-Object { $_.Action -eq 'Removed' }).Count
        $totalSize = ($history | Where-Object { $_.SizeMB } | Measure-Object -Property SizeMB -Sum).Sum

        Write-Host "  Summary: " -ForegroundColor Cyan -NoNewline
        Write-Host "$installCount installed" -ForegroundColor Green -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host "$updateCount updated" -ForegroundColor Yellow -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host "$removeCount removed" -ForegroundColor Red
        if ($totalSize) {
            Write-Host "  Total size: " -ForegroundColor Cyan -NoNewline
            Write-Host "$([Math]::Round($totalSize, 1)) MB" -ForegroundColor White
        }
        Write-Host ""

        # HTML Export
        if ($ExportHtml) {
            $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $exportPath = Join-Path $env:TEMP "WingetBatch_History_$timestamp.html"
            try {
                Export-WingetHtmlReport -Data $history -ReportTitle "Installation History ($dateRange)" -FilePath $exportPath
                if (Test-Path $exportPath) {
                    Write-Host "  [OK] Report saved: $exportPath" -ForegroundColor Green
                    Invoke-Item $exportPath
                }
            } catch {
                Write-Host "  [FAIL] Could not generate report: $_" -ForegroundColor Red
            }
        }
    }
}
