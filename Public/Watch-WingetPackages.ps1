function Watch-WingetPackages {
    <#
    .SYNOPSIS
        Live terminal dashboard for monitoring winget package state.

    .DESCRIPTION
        Displays a real-time refreshing dashboard showing:
        - Total installed packages count
        - Packages with available updates
        - Recently installed packages (last 7 days)
        - Source health status
        - Disk usage by package source
        - System winget version and health

        Refreshes automatically at a configurable interval. Press Ctrl+C to exit.

    .PARAMETER RefreshInterval
        Seconds between dashboard refreshes. Default: 30.

    .PARAMETER Once
        Display the dashboard once and exit (no refresh loop).

    .EXAMPLE
        Watch-WingetPackages
        Shows the live dashboard, refreshing every 30 seconds.

    .EXAMPLE
        Watch-WingetPackages -RefreshInterval 60
        Refresh every 60 seconds.

    .EXAMPLE
        Watch-WingetPackages -Once
        Show dashboard once (useful for scripts/CI).

    .LINK
        https://github.com/thebubbsy/WingetBatch
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(5, 3600)]
        [int]$RefreshInterval = 30,

        [Parameter()]
        [switch]$Once
    )

    begin {
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch {
                Write-Error "Microsoft.WinGet.Client module is required."
                return
            }
        }
        if (-not (Get-Module -Name PwshSpectreConsole)) {
            if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
                Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
            }
        }
    }

    process {
        function Get-DashboardData {
            $data = @{}

            # Winget version
            try {
                $data['WingetVersion'] = (Get-WinGetVersion -ErrorAction Stop).ToString()
                $data['WingetHealthy'] = $true
            } catch {
                $data['WingetVersion'] = 'N/A'
                $data['WingetHealthy'] = $false
            }

            # Installed packages
            $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
            $data['TotalPackages'] = if ($installed) { $installed.Count } else { 0 }

            # Updates available
            $updates = @()
            if ($installed) {
                $updates = @($installed | Where-Object { $_.IsUpdateAvailable })
            }
            $data['UpdatesAvailable'] = $updates.Count
            $data['UpdateList'] = $updates | Select-Object -First 10 Id, Name, InstalledVersion, AvailableVersion

            # Source breakdown
            $sourceGroups = @{}
            if ($installed) {
                foreach ($pkg in $installed) {
                    $src = if ($pkg.Source) { $pkg.Source } else { 'unknown' }
                    if (-not $sourceGroups.ContainsKey($src)) { $sourceGroups[$src] = 0 }
                    $sourceGroups[$src]++
                }
            }
            $data['Sources'] = $sourceGroups

            # Recently installed (from registry - last 7 days)
            $recentCount = 0
            try {
                $regPaths = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
                )
                $sevenDaysAgo = (Get-Date).AddDays(-7)
                foreach ($regPath in $regPaths) {
                    $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue |
                        Where-Object { $_.InstallDate }
                    foreach ($entry in $entries) {
                        try {
                            $installDate = [DateTime]::ParseExact($entry.InstallDate, 'yyyyMMdd', $null)
                            if ($installDate -ge $sevenDaysAgo) { $recentCount++ }
                        } catch {}
                    }
                }
            } catch {}
            $data['RecentInstalls'] = $recentCount

            # Winget source index age
            $wingetDir = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\Microsoft.Winget.Source_8wekyb3d8bbwe\winget"
            if (Test-Path "$wingetDir\source.db") {
                $dbAge = (Get-Date) - (Get-Item "$wingetDir\source.db").LastWriteTime
                $data['IndexAge'] = "$([Math]::Floor($dbAge.TotalHours))h ago"
                $data['IndexStale'] = $dbAge.TotalDays -gt 7
            } else {
                $data['IndexAge'] = 'Unknown'
                $data['IndexStale'] = $false
            }

            # GitHub token status
            $data['GitHubAuth'] = $false
            try {
                $token = Get-WingetBatchGitHubToken
                if ($token) { $data['GitHubAuth'] = $true }
            } catch {}

            $data['Timestamp'] = Get-Date
            return $data
        }

        function Show-Dashboard {
            param($data)

            # Clear screen
            [Console]::Clear()

            $border = '═' * 62
            $thinBorder = '─' * 62

            Write-Host ""
            Write-Host "  ╔$border╗" -ForegroundColor Cyan
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "  WINGETBATCH LIVE DASHBOARD" -ForegroundColor White -NoNewline
            $padRight = 62 - 30
            Write-Host (" " * $padRight) -NoNewline
            Write-Host "║" -ForegroundColor Cyan
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            $timeStr = "  Last refresh: $($data.Timestamp.ToString('HH:mm:ss'))"
            Write-Host $timeStr -ForegroundColor DarkGray -NoNewline
            $padRight2 = 62 - $timeStr.Length
            Write-Host (" " * $padRight2) -NoNewline
            Write-Host "║" -ForegroundColor Cyan
            Write-Host "  ╠$border╣" -ForegroundColor Cyan

            # System Health Row
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "  SYSTEM HEALTH" -ForegroundColor Yellow -NoNewline
            Write-Host (" " * (62 - 15)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            $wingetStatus = if ($data.WingetHealthy) { "[OK]" } else { "[!!]" }
            $wingetColor = if ($data.WingetHealthy) { 'Green' } else { 'Red' }
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    Winget Engine:    " -ForegroundColor Gray -NoNewline
            Write-Host "$wingetStatus v$($data.WingetVersion)" -ForegroundColor $wingetColor -NoNewline
            Write-Host (" " * (62 - 23 - $wingetStatus.Length - $data.WingetVersion.ToString().Length - 2)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            $indexStatus = if ($data.IndexStale) { "[STALE]" } else { "[FRESH]" }
            $indexColor = if ($data.IndexStale) { 'Yellow' } else { 'Green' }
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    Source Index:     " -ForegroundColor Gray -NoNewline
            Write-Host "$indexStatus ($($data.IndexAge))" -ForegroundColor $indexColor -NoNewline
            $idxLen = 23 + $indexStatus.Length + $data.IndexAge.Length + 3
            Write-Host (" " * [Math]::Max(0, 62 - $idxLen)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            $authStatus = if ($data.GitHubAuth) { "[AUTHENTICATED]" } else { "[ANONYMOUS]" }
            $authColor = if ($data.GitHubAuth) { 'Green' } else { 'DarkGray' }
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    GitHub API:       " -ForegroundColor Gray -NoNewline
            Write-Host $authStatus -ForegroundColor $authColor -NoNewline
            $authLen = 23 + $authStatus.Length
            Write-Host (" " * [Math]::Max(0, 62 - $authLen)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host (" " * 62) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            # Package Stats Row
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "  PACKAGE STATISTICS" -ForegroundColor Yellow -NoNewline
            Write-Host (" " * (62 - 20)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    Total Installed:  " -ForegroundColor Gray -NoNewline
            Write-Host "$($data.TotalPackages)" -ForegroundColor White -NoNewline
            $totalLen = 23 + $data.TotalPackages.ToString().Length
            Write-Host (" " * [Math]::Max(0, 62 - $totalLen)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            $updateColor = if ($data.UpdatesAvailable -gt 0) { 'Yellow' } else { 'Green' }
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    Updates Pending:  " -ForegroundColor Gray -NoNewline
            Write-Host "$($data.UpdatesAvailable)" -ForegroundColor $updateColor -NoNewline
            $updLen = 23 + $data.UpdatesAvailable.ToString().Length
            Write-Host (" " * [Math]::Max(0, 62 - $updLen)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    Recent (7 days):  " -ForegroundColor Gray -NoNewline
            Write-Host "$($data.RecentInstalls)" -ForegroundColor White -NoNewline
            $recLen = 23 + $data.RecentInstalls.ToString().Length
            Write-Host (" " * [Math]::Max(0, 62 - $recLen)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host (" " * 62) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            # Source Breakdown
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "  SOURCE BREAKDOWN" -ForegroundColor Yellow -NoNewline
            Write-Host (" " * (62 - 18)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            foreach ($src in $data.Sources.Keys | Sort-Object) {
                $count = $data.Sources[$src]
                $srcColor = if ($src -eq 'msstore') { 'Magenta' } elseif ($src -eq 'winget') { 'Cyan' } else { 'Gray' }
                $line = "    $($src): $($count)"
                Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                Write-Host "    " -NoNewline
                Write-Host "$src" -ForegroundColor $srcColor -NoNewline
                Write-Host ": $count" -ForegroundColor White -NoNewline
                Write-Host (" " * [Math]::Max(0, 62 - $line.Length - 4)) -NoNewline
                Write-Host "║" -ForegroundColor Cyan
            }

            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host (" " * 62) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            # Pending Updates (top 5)
            if ($data.UpdatesAvailable -gt 0) {
                Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                Write-Host "  PENDING UPDATES (top 5)" -ForegroundColor Yellow -NoNewline
                Write-Host (" " * (62 - 25)) -NoNewline
                Write-Host "║" -ForegroundColor Cyan

                $shown = 0
                foreach ($upd in $data.UpdateList) {
                    if ($shown -ge 5) { break }
                    $line = "    $($upd.Id): $($upd.InstalledVersion) -> $($upd.AvailableVersion)"
                    if ($line.Length -gt 60) { $line = $line.Substring(0, 57) + "..." }
                    Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                    Write-Host $line -ForegroundColor DarkGray -NoNewline
                    Write-Host (" " * [Math]::Max(0, 62 - $line.Length)) -NoNewline
                    Write-Host "║" -ForegroundColor Cyan
                    $shown++
                }

                if ($data.UpdatesAvailable -gt 5) {
                    Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                    Write-Host "    ... and $($data.UpdatesAvailable - 5) more" -ForegroundColor DarkGray -NoNewline
                    $moreLine = "    ... and $($data.UpdatesAvailable - 5) more"
                    Write-Host (" " * [Math]::Max(0, 62 - $moreLine.Length)) -NoNewline
                    Write-Host "║" -ForegroundColor Cyan
                }

                Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                Write-Host (" " * 62) -NoNewline
                Write-Host "║" -ForegroundColor Cyan
            }

            # Footer
            Write-Host "  ╠$border╣" -ForegroundColor Cyan
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            $footer = "  Refresh: ${RefreshInterval}s | Ctrl+C to exit | Get-WingetUpdates to update"
            Write-Host $footer -ForegroundColor DarkGray -NoNewline
            Write-Host (" " * [Math]::Max(0, 62 - $footer.Length)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan
            Write-Host "  ╚$border╝" -ForegroundColor Cyan
            Write-Host ""
        }

        # Main loop
        do {
            $dashboardData = Get-DashboardData
            Show-Dashboard -data $dashboardData

            if ($Once) { break }

            Start-Sleep -Seconds $RefreshInterval
        } while ($true)
    }
}
