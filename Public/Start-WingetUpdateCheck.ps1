function Start-WingetUpdateCheck {
    <#
    .SYNOPSIS
        Checks for winget updates in the background.

    .DESCRIPTION
        This command is typically triggered by your PowerShell profile if you've enabled update notifications via Enable-WingetUpdateNotifications.
        It prints the last known update count straight away, then refreshes the list in a background job and pops a
        Windows notification if any updates are found. Results are cached so Get-WingetUpdates can show them instantly.
        It respects the interval set in the configuration.

    .PARAMETER Force
        Ignore the configured check interval and check immediately.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $configDir = Get-WingetBatchConfigDir
    $config = Get-WingetBatchConfigData
    if (-not $config['UpdateNotificationsEnabled']) {
        return
    }

    $cacheFile = Join-Path $configDir "update_cache.json"

    # Show what we already know without waiting for a new check
    if (Test-Path $cacheFile) {
        try {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $count = if ($null -ne $cache.UpdateCount) { [int]$cache.UpdateCount } else { @($cache.Updates).Count }
            if ($count -gt 0) {
                Write-Host "$count winget package update(s) available - run " -ForegroundColor Yellow -NoNewline
                Write-Host "Get-WingetUpdates" -ForegroundColor White
            }
        }
        catch { }
    }

    if (-not $Force) {
        if ($config['LastCheck']) {
            try {
                $lastCheckTime = [datetime]$config['LastCheck']
                $interval = [double]$config['CheckInterval']
                if ($interval -gt 0 -and (Get-Date) -lt $lastCheckTime.AddHours($interval)) {
                    return
                }
                if ($interval -le 0 -and -not $config['CheckOnStartup']) {
                    return
                }
            } catch {
                # Invalid date format, just proceed
            }
        } elseif (-not $config['CheckOnStartup']) {
            # First run with startup checks disabled: start the interval clock now
            $config['LastCheck'] = (Get-Date).ToString("o")
            Save-WingetBatchConfigData -Config $config
            return
        }
    }

    # Update LastCheck immediately to prevent multiple rapid checks from multiple terminal sessions
    $config['LastCheck'] = (Get-Date).ToString("o")
    Save-WingetBatchConfigData -Config $config

    $jobScript = {
        param($CacheFile)
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            $updates = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction Stop | Where-Object { $_.IsUpdateAvailable } | ForEach-Object {
                [PSCustomObject]@{
                    Id               = $_.Id
                    Name             = $_.Name
                    InstalledVersion = $_.InstalledVersion
                    AvailableVersion = @($_.AvailableVersions)[0]
                    Source           = $_.Source
                }
            })

            # Same format Get-WingetUpdates reads, so it can skip its own scan
            @{
                LastChecked = (Get-Date).ToString('o')
                UpdateCount = $updates.Count
                Updates     = $updates
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $CacheFile -Encoding UTF8

            if ($updates.Count -gt 0) {
                $names = @($updates | Select-Object -First 3 | ForEach-Object { if ($_.Name) { $_.Name } else { $_.Id } })
                $pkgText = $names -join ", "
                if ($updates.Count -gt 3) {
                    $pkgText += " and $($updates.Count - 3) more"
                }

                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing
                $balloon = New-Object System.Windows.Forms.NotifyIcon
                $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $PID).Path)
                $balloon.BalloonTipIcon = "Info"
                $balloon.BalloonTipTitle = "Winget Updates Available ($($updates.Count))"
                $balloon.BalloonTipText = "Updates available for: $pkgText.`nRun 'Get-WingetUpdates' to install."
                $balloon.Visible = $true
                $balloon.ShowBalloonTip(10000)
                Start-Sleep -Seconds 10
                $balloon.Dispose()
            }
        } catch {
            # Ignore background job errors so it fails silently in profile
        }
    }

    # Start the check in a background job so it doesn't block the user's terminal startup
    Start-Job -ScriptBlock $jobScript -ArgumentList (Join-Path $configDir "update_cache.json") -Name "WingetUpdateCheck" | Out-Null
}
