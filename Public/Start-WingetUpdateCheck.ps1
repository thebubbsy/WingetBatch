function Start-WingetUpdateCheck {
    <#
    .SYNOPSIS
        Checks for winget updates in the background.

    .DESCRIPTION
        This command is typically triggered by your PowerShell profile if you've enabled update notifications via Enable-WingetUpdateNotifications.
        It runs winget upgrade in a background job and pops a native Windows toast notification if any updates are found.
        It respects the interval set in the configuration.

    .PARAMETER Force
        Ignore the configured check interval and check immediately.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $configDir = Get-WingetBatchConfigDir
    $configFile = Join-Path $configDir "config.json"

    if (-not (Test-Path $configFile)) {
        return
    }

    $config = Get-Content $configFile -Raw | ConvertFrom-Json
    if (-not $config.UpdateNotificationsEnabled) {
        return
    }

    if (-not $Force) {
        if ($config.LastCheck) {
            try {
                $lastCheckTime = [datetime]$config.LastCheck
                $interval = $config.CheckInterval
                if ($interval -gt 0 -and (Get-Date) -lt $lastCheckTime.AddHours($interval)) {
                    return
                }
            } catch {
                # Invalid date format, just proceed
            }
        } elseif (-not $config.CheckOnStartup) {
            # No LastCheck, but CheckOnStartup is false.
            $config.LastCheck = (Get-Date).ToString("o")
            $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force
            return
        }
    }

    # Update LastCheck immediately to prevent multiple rapid checks from multiple terminal sessions
    $config.LastCheck = (Get-Date).ToString("o")
    $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force

    $jobScript = {
        try {
            $updates = winget upgrade 2>&1
            $updateCount = 0
            $packages = @()
            
            foreach ($line in $updates) {
                if ($line -match '^\s*[a-zA-Z]') {
                    # Filter out headers, empty lines, and non-package winget outputs
                    if ($line -notmatch 'Name\s+|Id\s+|Version\s+|Available\s+|Source\s+|-{5,}|No installed package found|Failed in attempting to update|upgrades available') {
                        $updateCount++
                        if ($packages.Count -lt 3) {
                            $parts = $line -split '\s{2,}'
                            if ($parts.Count -gt 0) {
                                $packages += $parts[0].Trim()
                            }
                        }
                    }
                }
            }

            if ($updateCount -gt 0) {
                $pkgText = $packages -join ", "
                if ($updateCount -gt 3) {
                    $pkgText += " and $($updateCount - 3) more"
                }

                Add-Type -AssemblyName System.Windows.Forms
                $balloon = New-Object System.Windows.Forms.NotifyIcon
                $path = (Get-Process -id $pid).Path
                $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
                $balloon.BalloonTipIcon = "Info"
                $balloon.BalloonTipTitle = "Winget Updates Available ($updateCount)"
                $balloon.BalloonTipText = "Updates available for: $pkgText.`nRun 'Invoke-WinGetBatch' to install."
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
    Start-Job -ScriptBlock $jobScript -Name "WingetUpdateCheck" | Out-Null
}
