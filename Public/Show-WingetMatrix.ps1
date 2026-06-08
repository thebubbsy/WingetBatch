function Show-WingetMatrix {
    <#
    .SYNOPSIS
        Displays installed packages falling like The Matrix.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$DurationSeconds = 5
    )

    Write-Host "Initializing The Matrix..." -ForegroundColor DarkGreen
    Start-Sleep -Seconds 1

    # Only get IDs to be fast
    $packages = winget list | Select-String -Pattern '\s+([A-Za-z][A-Za-z0-9]*\.[A-Za-z0-9][A-Za-z0-9\.\-_]*)\s+' | ForEach-Object {
        if ($_.Line -match '\s+([A-Za-z][A-Za-z0-9]*\.[A-Za-z0-9][A-Za-z0-9\.\-_]*)\s+') {
            $matches[1]
        }
    }

    if ($packages.Count -eq 0) {
        $packages = @("System32.Dll", "Microsoft.Windows", "Matrix.Core", "Neo.Awake", "Morpheus.Pill")
    }

    $startTime = Get-Date
    $width = $Host.UI.RawUI.WindowSize.Width
    if ($width -le 0) { $width = 80 }

    Clear-Host

    while (((Get-Date) - $startTime).TotalSeconds -lt $DurationSeconds) {
        $pkg = $packages | Get-Random
        $spaces = " " * (Get-Random -Minimum 0 -Maximum ($width - $pkg.Length - 1))
        
        $color = @("Green", "DarkGreen", "Cyan", "DarkCyan") | Get-Random
        
        Write-Host "$spaces$pkg" -ForegroundColor $color
        Start-Sleep -Milliseconds (Get-Random -Minimum 10 -Maximum 100)
    }

    Clear-Host
    Write-Host "Wake up, Neo... The winget batch update has you." -ForegroundColor Green
    Write-Host ""
}