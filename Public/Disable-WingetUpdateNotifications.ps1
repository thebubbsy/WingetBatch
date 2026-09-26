function Disable-WingetUpdateNotifications {
    <#
    .SYNOPSIS
        Disable automatic winget update notifications.

    .DESCRIPTION
        Removes the update check from your PowerShell profile and disables notifications.

    .EXAMPLE
        Disable-WingetUpdateNotifications
        Disables update notifications.
    #>

    [CmdletBinding()]
    param()

    # Update configuration (merge, so other settings are kept)
    $config = Get-WingetBatchConfigData
    if ($config.Count -gt 0) {
        $config['UpdateNotificationsEnabled'] = $false
        Save-WingetBatchConfigData -Config $config
    }

    # Remove from profile
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (Test-Path $profilePath) {
        $profileContent = Get-Content $profilePath -Raw

        # Remove the WingetBatch initialization block
        $pattern = '(?s)# WingetBatch - Update Notifications.*?Start-WingetUpdateCheck\s*\}'
        $newContent = $profileContent -replace $pattern, ''

        $newContent | Out-File -FilePath $profilePath -Encoding UTF8 -Force
    }

    Write-Host "✓ Update notifications disabled" -ForegroundColor Green
    Write-Host "  Restart your terminal for changes to take effect." -ForegroundColor DarkGray
}

