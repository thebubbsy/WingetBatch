function Invoke-WingetRussianRoulette {
    <#
    .SYNOPSIS
        Picks a random package from winget and installs it.
    .DESCRIPTION
        Extremely chaotic feature. Pulls a random package from the Winget repository and attempts to install it.
    .PARAMETER Confirm
        Prompt for confirmation before installing a random package.
    .PARAMETER YOLO
        Skip all confirmations and just do it.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$YOLO
    )

    Write-Host "Spinning the Winget cylinder..." -ForegroundColor Red

    # Search for random letter to get a large pool
    $letters = "abcdefghijklmnopqrstuvwxyz".ToCharArray()
    $randomLetter = $letters | Get-Random

    $results = winget search $randomLetter --accept-source-agreements 2>&1
    $packages = @()

    foreach ($line in $results) {
        if ($line -match '\s+([A-Za-z][A-Za-z0-9]*\.[A-Za-z0-9][A-Za-z0-9\.\-_]*)\s+') {
            $packages += $matches[1].Trim()
        }
    }

    if ($packages.Count -eq 0) {
        Write-Host "The chamber was empty. You survived." -ForegroundColor Green
        return
    }

    $target = $packages | Get-Random
    Write-Host "CLICK! The hammer strikes on: " -NoNewline -ForegroundColor Yellow
    Write-Host $target -ForegroundColor Red

    if (-not $YOLO) {
        $confirm = Read-Host "Are you sure you want to install $target? (y/N)"
        if ($confirm -notmatch "^y") {
            Write-Host "You pulled away from the table. The package was not installed." -ForegroundColor DarkGray
            return
        }
    }

    Write-Host "Installing $target..." -ForegroundColor Cyan
    winget install --id $target --accept-package-agreements --accept-source-agreements
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Installation successful! Enjoy your random software." -ForegroundColor Green
    } else {
        Write-Host "Installation failed. The software gods spared your system." -ForegroundColor DarkYellow
    }
}