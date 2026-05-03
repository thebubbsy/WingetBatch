function Get-WingetUpdates {
    <#
    .SYNOPSIS
        Check for and install available winget package updates.

    .DESCRIPTION
        Displays a list of all installed winget packages that have updates available,
        with an interactive selection to choose which ones to update.

    .PARAMETER Force
        Skip the cache and force a fresh check for updates.

    .EXAMPLE
        Get-WingetUpdates
        Shows available updates and allows you to select which to install.

    .EXAMPLE
        Get-WingetUpdates -Force
        Forces a fresh check for updates.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$IWantToLiterallyUpdateAllFuckingResults
    )

    # Ensure PwshSpectreConsole is available
    if (-not (Get-Module -Name PwshSpectreConsole)) {
        if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Checking for winget package updates..." -ForegroundColor Cyan

    # Check cache first
    $cacheFile = Join-Path (Get-WingetBatchConfigDir) "update_cache.json"
    $useCache = $false

    if (-not $Force -and (Test-Path $cacheFile)) {
        $cache = Get-Content $cacheFile | ConvertFrom-Json
        $cacheAge = ((Get-Date) - [DateTime]::Parse($cache.LastChecked)).TotalMinutes

        if ($cacheAge -lt 30) {
            $useCache = $true
            $updatesAvailable = $cache.Updates
            Write-Host "Using cached results (checked $([Math]::Round($cacheAge, 0)) minutes ago)" -ForegroundColor DarkGray
        }
    }

    if (-not $useCache) {
        # Get list of packages with updates available
        $upgradeOutput = winget upgrade --disable-interactivity 2>&1 | Out-String
        $upgradeLines = $upgradeOutput -split "`n"
        $updatesAvailable = [System.Collections.Generic.List[Object]]::new()
        $seenIds = @{}

        $headerFound = $false
        foreach ($line in $upgradeLines) {
            if ($line -match '^-+') {
                $headerFound = $true
                continue
            }

            if ($headerFound -and $line.Trim() -ne '' -and $line -notmatch 'upgrades available' -and $line -notmatch 'package\(s\) have version') {
                # Parse the table format and extract package ID
                if ($line -match '\s+([A-Za-z][A-Za-z0-9]*\.[A-Za-z0-9][A-Za-z0-9\.\-_]*)\s+') {
                    $packageId = $matches[1].Trim()

                    # Only add if it hasn't been seen
                    if (-not $seenIds.ContainsKey($packageId)) {
                        # Store the entire line for display
                        $updatesAvailable.Add(@{
                            Id = $packageId
                            DisplayLine = $line.Trim()
                        })
                        $seenIds[$packageId] = $true
                    }
                }
            }
        }
    }

    if ($updatesAvailable.Count -eq 0) {
        Write-Host "[OK] All packages are up to date!" -ForegroundColor Green
        return
    }

    Write-Host ""
                            Write-Host "  - " -ForegroundColor Green -NoNewline
    Write-Host "$($updatesAvailable.Count)" -ForegroundColor White -NoNewline
    Write-Host " update(s) available" -ForegroundColor Green
    Write-Host ""

    # Interactive selection using Spectre Console
    if ($IWantToLiterallyUpdateAllFuckingResults) {
        $selectedPackages = $updatesAvailable | ForEach-Object { $_.Id }
    }
    elseif (Get-Module -Name PwshSpectreConsole) {
        try {
            # Create a lookup table: DisplayLine -> Id
            $displayToId = @{}
            $displayLines = $updatesAvailable | ForEach-Object {
                $displayToId[$_.DisplayLine] = $_.Id
                $_.DisplayLine
            }

            $selectedLines = Read-SpectreMultiSelection -Title "[cyan]Select packages to update (Space to toggle, Enter to confirm)[/]" `
                -Choices $displayLines `
                -PageSize 20 `
                -Color "Green"

            if ($selectedLines.Count -eq 0) {
                Write-Host "No packages selected." -ForegroundColor Yellow
                return
            }

            # Convert selected display lines back to package IDs
            $selectedPackages = $selectedLines | ForEach-Object { $displayToId[$_] }
        }
        catch {
            Write-Warning "Interactive selection error: $_"
            Write-Host "Packages with updates available:" -ForegroundColor Cyan
            $updatesAvailable | ForEach-Object {
                Write-Host "  â€¢ $($_.Id)" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "Use 'winget upgrade <PackageName>' to update manually." -ForegroundColor Yellow
            return
        }
    }
    else {
        # Fallback without interactive selection
        Write-Host "Packages with updates available:" -ForegroundColor Cyan
        $updatesAvailable | ForEach-Object {
            Write-Host "  â€¢ $($_.Id)" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "To update a package: " -ForegroundColor Cyan -NoNewline
        Write-Host "winget upgrade <PackageName>" -ForegroundColor Yellow
        Write-Host "To update all: " -ForegroundColor Cyan -NoNewline
        Write-Host "winget upgrade --all" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Updating " -ForegroundColor Cyan -NoNewline
    Write-Host "$($selectedPackages.Count)" -ForegroundColor White -NoNewline
    Write-Host " package(s)..." -ForegroundColor Cyan
    Write-Host ""

    $successCount = 0
    $failCount = 0

    foreach ($packageId in $selectedPackages) {
        Write-Host ">>> Updating: " -ForegroundColor Magenta -NoNewline
        Write-Host $packageId -ForegroundColor White

        winget upgrade --id $packageId --accept-package-agreements --accept-source-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Successfully updated " -ForegroundColor Green -NoNewline
            Write-Host $packageId -ForegroundColor White
            $successCount++
        }
        else {
            Write-Host "[FAIL] Failed to update " -ForegroundColor Red -NoNewline
            Write-Host $packageId -ForegroundColor White
            $failCount++
        }
        Write-Host ""
    }

    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "Update Complete" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green
                            Write-Host "  - " -ForegroundColor Green -NoNewline
    Write-Host $successCount -ForegroundColor White -NoNewline
    Write-Host " | Failed: " -ForegroundColor Red -NoNewline
    Write-Host $failCount -ForegroundColor White

    # Clear cache after updates
    if (Test-Path $cacheFile) {
        Remove-Item $cacheFile -Force
    }
}


