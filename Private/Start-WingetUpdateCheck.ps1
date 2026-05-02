function Start-WingetUpdateCheck {
    <#
    .SYNOPSIS
        Internal function that runs the update check and displays notifications.

    .DESCRIPTION
        This function is called automatically from your PowerShell profile.
        It checks if updates are available and displays a notification.
    #>

    [CmdletBinding()]
    param()

    $configDir = Get-WingetBatchConfigDir
    $configFile = Join-Path $configDir "config.json"
    $cacheFile = Join-Path $configDir "update_cache.json"

    # Check if notifications are enabled
    if (-not (Test-Path $configFile)) {
        return
    }

    $config = Get-Content $configFile | ConvertFrom-Json

    if (-not $config.UpdateNotificationsEnabled) {
        return
    }

    # Check if we should run based on interval
    $shouldCheck = $false

    if ($config.CheckOnStartup -and -not $config.LastCheck) {
        $shouldCheck = $true
    }
    elseif ($config.LastCheck) {
        $lastCheck = [DateTime]::Parse($config.LastCheck)
        $hoursSinceCheck = ((Get-Date) - $lastCheck).TotalHours

        if ($config.CheckInterval -gt 0 -and $hoursSinceCheck -ge $config.CheckInterval) {
            $shouldCheck = $true
        }
        elseif ($config.CheckOnStartup) {
            $shouldCheck = $true
        }
    }
    else {
        $shouldCheck = $true
    }

    if (-not $shouldCheck) {
        # Load cached results if available
        if (Test-Path $cacheFile) {
            $cache = Get-Content $cacheFile | ConvertFrom-Json
            if ($cache.UpdateCount -gt 0) {
                Write-Host ""
                Write-Host "📦 " -NoNewline -ForegroundColor Cyan
                Write-Host "$($cache.UpdateCount) winget package update(s) available" -ForegroundColor Yellow
                Write-Host "   Run " -NoNewline -ForegroundColor DarkGray
                Write-Host "Get-WingetUpdates" -NoNewline -ForegroundColor White
                Write-Host " to view and install them" -ForegroundColor DarkGray
            }
        }
        return
    }

    # Run check in background job
    $job = Start-WingetBatchJob -ScriptBlock {
        param($configDir, $cacheFile)

        try {
            # Get list of packages with updates available
            $upgradeOutput = winget upgrade --disable-interactivity 2>&1 | Out-String
            $upgradeLines = $upgradeOutput -split "`n"
            $updatesAvailable = [System.Collections.Generic.List[Object]]::new()

            $headerFound = $false
            foreach ($line in $upgradeLines) {
                if ($line -match '^-+') {
                    $headerFound = $true
                    continue
                }

                if ($headerFound -and $line.Trim() -ne '' -and $line -notmatch 'upgrades available') {
                    # Extract package info
                    if ($line -match '([A-Za-z0-9\.\-_]+\.[A-Za-z0-9\.\-_]+)') {
                        $packageId = $matches[1].Trim()

                        # Try to get version info
                        if ($line -match '<\s*(.+?)\s*>') {
                            $installedVer = $matches[1].Trim()
                        }
                        else {
                            $installedVer = "Unknown"
                        }

                        $updatesAvailable.Add(@{
                            Id = $packageId
                            CurrentVersion = $installedVer
                        })
                    }
                }
            }

            # Save cache
            $cache = @{
                UpdateCount = $updatesAvailable.Count
                Updates = $updatesAvailable
                LastChecked = (Get-Date).ToString('o')
            }

            $cache | ConvertTo-Json | Out-File -FilePath $cacheFile -Encoding UTF8 -Force

            return $updatesAvailable.Count

        }
        catch {
            return -1
        }
    } -ArgumentList $configDir, $cacheFile

    # Update last check time
    $config.LastCheck = (Get-Date).ToString('o')
    $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force

    # Wait briefly for job (non-blocking)
    Wait-Job -Job $job -Timeout 10 | Out-Null

    if ($job.State -eq 'Completed') {
        $updateCount = Receive-Job -Job $job

        if ($updateCount -gt 0) {
            Write-Host ""
            Write-Host "📦 " -NoNewline -ForegroundColor Cyan
            Write-Host "$updateCount winget package update(s) available" -ForegroundColor Yellow
            Write-Host "   Run " -NoNewline -ForegroundColor DarkGray
            Write-Host "Get-WingetUpdates" -NoNewline -ForegroundColor White
            Write-Host " to view and install them" -ForegroundColor DarkGray
        }
    }

    Remove-Job -Job $job -Force
}
