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
                $data['WingetVersion'] = (Microsoft.WinGet.Client\Get-WinGetVersion -ErrorAction Stop).ToString()
                $data['WingetHealthy'] = $true
            } catch {
                $data['WingetVersion'] = 'N/A'
                $data['WingetHealthy'] = $false
            }

            # Installed packages
            $installed = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue)
            $data['TotalPackages'] = if ($installed) { $installed.Count } else { 0 }

            # Updates available
            $updates = @()
            if ($installed) {
                $updates = @($installed | Where-Object { $_.IsUpdateAvailable })
            }
            $data['UpdatesAvailable'] = $updates.Count
            $data['UpdateList'] = $updates | Select-Object -First 10 Id, Name, InstalledVersion, @{ Name = 'AvailableVersion'; Expression = { @($_.AvailableVersions)[0] } }

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
            $indexAge = Get-WingetSourceIndexAge
            if ($null -ne $indexAge) {
                $data['IndexAge'] = if ($indexAge.TotalHours -lt 48) { "$([Math]::Floor($indexAge.TotalHours))h ago" } else { "$([Math]::Floor($indexAge.TotalDays))d ago" }
                $data['IndexStale'] = $indexAge.TotalDays -gt 7
            } else {
                $data['IndexAge'] = 'Unknown'
                $data['IndexStale'] = $null
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

            # Clear screen between refreshes (not possible when output is redirected, e.g. -Once in CI)
            if (-not $Once -and -not [Console]::IsOutputRedirected) {
                try { [Console]::Clear() } catch { }
            }

            $width = 62
            $border = '═' * $width

            # One boxed row made of colored segments, padded to the box width
            function Write-Row {
                param([object[]]$Parts = @())
                Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                $len = 0
                for ($i = 0; $i -lt $Parts.Count; $i += 2) {
                    $text = [string]$Parts[$i]
                    $room = $width - $len
                    if ($room -le 0) { break }
                    if ($text.Length -gt $room) { $text = $text.Substring(0, [Math]::Max(0, $room - 3)) + '...' }
                    Write-Host $text -ForegroundColor $Parts[$i + 1] -NoNewline
                    $len += $text.Length
                }
                Write-Host (' ' * [Math]::Max(0, $width - $len)) -NoNewline
                Write-Host "║" -ForegroundColor Cyan
            }

            Write-Host ""
            Write-Host "  ╔$border╗" -ForegroundColor Cyan
            Write-Row @('  WINGETBATCH LIVE DASHBOARD', 'White')
            Write-Row @("  Last refresh: $($data.Timestamp.ToString('HH:mm:ss'))", 'DarkGray')
            Write-Host "  ╠$border╣" -ForegroundColor Cyan

            # System Health
            Write-Row @('  SYSTEM HEALTH', 'Yellow')
            $ver = ([string]$data.WingetVersion).TrimStart('v')
            if ($data.WingetHealthy) { Write-Row @('    Winget Engine:    ', 'Gray', "[OK] v$ver", 'Green') }
            else { Write-Row @('    Winget Engine:    ', 'Gray', '[!!] unavailable', 'Red') }
            $indexStatus = if ($null -eq $data.IndexStale) { "[?]" } elseif ($data.IndexStale) { "[STALE]" } else { "[FRESH]" }
            Write-Row @('    Source Index:     ', 'Gray', "$indexStatus ($($data.IndexAge))", $(if ($data.IndexStale) { 'Yellow' } else { 'Green' }))
            Write-Row @('    GitHub API:       ', 'Gray', $(if ($data.GitHubAuth) { '[AUTHENTICATED]' } else { '[ANONYMOUS]' }), $(if ($data.GitHubAuth) { 'Green' } else { 'DarkGray' }))
            Write-Row

            # Package Stats
            Write-Row @('  PACKAGE STATISTICS', 'Yellow')
            Write-Row @('    Total Installed:  ', 'Gray', "$($data.TotalPackages)", 'White')
            Write-Row @('    Updates Pending:  ', 'Gray', "$($data.UpdatesAvailable)", $(if ($data.UpdatesAvailable -gt 0) { 'Yellow' } else { 'Green' }))
            Write-Row @('    Recent (7 days):  ', 'Gray', "$($data.RecentInstalls)", 'White')
            Write-Row

            # Source Breakdown
            Write-Row @('  SOURCE BREAKDOWN', 'Yellow')
            foreach ($src in $data.Sources.Keys | Sort-Object) {
                $srcColor = if ($src -eq 'msstore') { 'Magenta' } elseif ($src -eq 'winget') { 'Cyan' } else { 'Gray' }
                $label = if ($src -eq 'unknown') { 'no source (ARP/MSIX)' } else { $src }
                Write-Row @('    ', 'Gray', $label, $srcColor, ": $($data.Sources[$src])", 'White')
            }
            Write-Row

            # Pending Updates (top 5)
            if ($data.UpdatesAvailable -gt 0) {
                Write-Row @('  PENDING UPDATES (top 5)', 'Yellow')
                foreach ($upd in @($data.UpdateList) | Select-Object -First 5) {
                    Write-Row @("    $($upd.Id): $($upd.InstalledVersion) -> $($upd.AvailableVersion)", 'DarkGray')
                }
                if ($data.UpdatesAvailable -gt 5) {
                    Write-Row @("    ... and $($data.UpdatesAvailable - 5) more", 'DarkGray')
                }
                Write-Row
            }

            # Footer
            Write-Host "  ╠$border╣" -ForegroundColor Cyan
            $footer = if ($Once) { "  Get-WingetUpdates to install updates" } else { "  Refresh: ${RefreshInterval}s | Ctrl+C to exit | Get-WingetUpdates" }
            Write-Row @($footer, 'DarkGray')
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
