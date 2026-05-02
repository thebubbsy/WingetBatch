function Remove-WingetRecent {
    <#
    .SYNOPSIS
        Uninstall recently installed winget packages.

    .DESCRIPTION
        Shows packages installed in the last X days and allows interactive selection
        of which packages to uninstall.

    .PARAMETER Days
        Number of days to look back for recently installed packages. Default is 1 day.

    .EXAMPLE
        Remove-WingetRecent
        Shows packages installed in the last day and allows you to select which to uninstall.

    .EXAMPLE
        Remove-WingetRecent -Days 7
        Shows packages installed in the last 7 days.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Days = 1
    )

    # Ensure PwshSpectreConsole is available
    if (-not (Get-Module -Name PwshSpectreConsole)) {
        if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Searching for packages installed in the last " -ForegroundColor Cyan -NoNewline
    Write-Host "$Days day$(if ($Days -ne 1) { 's' })..." -ForegroundColor Yellow

    try {
        Write-Host "Reading Windows Registry for installation dates..." -ForegroundColor Cyan

        # Get installation dates from Windows Registry
        $uninstallPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        $registryApps = @{}
        foreach ($path in $uninstallPaths) {
            try {
                Get-ItemProperty $path -ErrorAction SilentlyContinue | ForEach-Object {
                    $displayName = $_.DisplayName
                    $installDate = $_.InstallDate

                    if ($displayName -and $installDate) {
                        # Parse InstallDate (format: YYYYMMDD)
                        try {
                            $year = $installDate.Substring(0, 4)
                            $month = $installDate.Substring(4, 2)
                            $day = $installDate.Substring(6, 2)
                            $date = [DateTime]::ParseExact("$year-$month-$day", "yyyy-MM-dd", $null)

                            if (-not $registryApps.ContainsKey($displayName)) {
                                $registryApps[$displayName] = $date
                            }
                        }
                        catch {
                            # Skip invalid dates
                        }
                    }
                }
            }
            catch {
                # Skip inaccessible registry paths
            }
        }

        Write-Host "Found installation dates for $($registryApps.Count) programs" -ForegroundColor DarkGray
        Write-Host ""

        # Get list of installed packages from winget
        $listOutput = winget list --disable-interactivity 2>&1 | Out-String
        $listLines = $listOutput -split "`n"

        $installedPackages = [System.Collections.Generic.List[Object]]::new()
        $seenIds = @{}
        $headerFound = $false
        $idColStart = -1
        $idColEnd = -1
        $nameColEnd = -1

        $cutoffDate = (Get-Date).AddDays(-$Days).Date

        foreach ($line in $listLines) {
            # Find the header line to determine column positions
            if ($line -match '^Name\s+Id\s+') {
                $nameColEnd = $line.IndexOf('Id') - 1
                $idColStart = $line.IndexOf('Id')
                if ($line -match 'Version') {
                    $idColEnd = $line.IndexOf('Version') - 1
                } else {
                    $idColEnd = $line.Length
                }
                continue
            }

            # Skip until we find the header separator line (dashes)
            if ($line -match '^-+') {
                $headerFound = $true
                continue
            }

            if ($headerFound -and $line.Trim() -ne '' -and $idColStart -gt 0 -and $line.Length -gt $idColStart) {
                # Extract package ID and Name
                $endPos = if ($idColEnd -lt $line.Length) { $idColEnd } else { $line.Length }
                $packageId = $line.Substring($idColStart, $endPos - $idColStart).Trim()
                $packageName = if ($nameColEnd -gt 0 -and $line.Length -gt $nameColEnd) {
                    $line.Substring(0, $nameColEnd).Trim()
                } else {
                    ""
                }

                # Only process valid package IDs and avoid duplicates
                if ($packageId -and $packageId -match '^[A-Za-z0-9\.\-_]+$' -and -not $seenIds.ContainsKey($packageId)) {
                    # Try to find installation date from registry
                    $installDate = $null

                    # Try exact name match first
                    if ($registryApps.ContainsKey($packageName)) {
                        $installDate = $registryApps[$packageName]
                    }
                    else {
                        # Try fuzzy match - check if registry name contains package name or vice versa
                        foreach ($regName in $registryApps.Keys) {
                            # Check if regName contains packageName
                            if ($regName.Length -ge $packageName.Length -and $regName.IndexOf($packageName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                $installDate = $registryApps[$regName]
                                break
                            }
                            # Check if packageName contains regName
                            if ($packageName.Length -ge $regName.Length -and $packageName.IndexOf($regName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                $installDate = $registryApps[$regName]
                                break
                            }
                        }
                    }

                    # Only add if within time window (or no date found and we show all)
                    if ($installDate -and $installDate -ge $cutoffDate) {
                        $installedPackages.Add(@{
                            Id = $packageId
                            Name = $packageName
                            InstallDate = $installDate
                            DisplayLine = $line.Trim()
                        })
                        $seenIds[$packageId] = $true
                    }
                }
            }
        }

        if ($installedPackages.Count -eq 0) {
            Write-Warning "No packages installed in the last $Days day$(if ($Days -ne 1) { 's' })."
            Write-Host "Note: Only packages with registry install dates can be tracked." -ForegroundColor DarkGray
            return
        }

        # Sort by install date (most recent first)
        $installedPackages = $installedPackages | Sort-Object -Property InstallDate -Descending

        Write-Host "Found " -ForegroundColor Green -NoNewline
        Write-Host "$($installedPackages.Count)" -ForegroundColor White -NoNewline
        Write-Host " package(s) installed in the last $Days day$(if ($Days -ne 1) { 's' })" -ForegroundColor Green
        Write-Host ""

        # Interactive selection using Spectre Console
        if (Get-Module -Name PwshSpectreConsole) {
            try {
                # Create a lookup table: DisplayLine -> Id with install date
                $displayToId = @{}
                $displayLines = $installedPackages | ForEach-Object {
                    $dateStr = $_.InstallDate.ToString('yyyy-MM-dd')
                    $displayText = "($dateStr) $($_.Id)"
                    $displayToId[$displayText] = $_.Id
                    $displayText
                }

                $selectedLines = Read-SpectreMultiSelection -Title "[red]⚠ Select packages to UNINSTALL (Space to toggle, Enter to confirm)[/]" `
                    -Choices $displayLines `
                    -PageSize 20 `
                    -Color "Red"

                if ($selectedLines.Count -eq 0) {
                    Write-Host "No packages selected." -ForegroundColor Yellow
                    return
                }

                # Convert selected display lines back to package IDs
                $selectedPackages = $selectedLines | ForEach-Object { $displayToId[$_] }

                Write-Host ""
                Write-Host "⚠ WARNING: " -ForegroundColor Red -NoNewline
                Write-Host "You are about to UNINSTALL " -ForegroundColor Yellow -NoNewline
                Write-Host "$($selectedPackages.Count)" -ForegroundColor White -NoNewline
                Write-Host " package(s):" -ForegroundColor Yellow
                Write-Host ""

                foreach ($pkgId in $selectedPackages) {
                    Write-Host "   • " -ForegroundColor Red -NoNewline
                    Write-Host $pkgId -ForegroundColor White
                }

                Write-Host ""
                Write-Host "Type " -NoNewline -ForegroundColor Yellow
                Write-Host "YES" -NoNewline -ForegroundColor Red
                Write-Host " to confirm uninstallation, or anything else to cancel: " -NoNewline -ForegroundColor Yellow
                $confirmation = Read-Host

                if ($confirmation -ne "YES") {
                    Write-Host "Uninstallation cancelled." -ForegroundColor Green
                    return
                }

                Write-Host ""
                Write-Host ("=" * 60) -ForegroundColor Red
                Write-Host "Starting Uninstallation Process" -ForegroundColor Red
                Write-Host ("=" * 60) -ForegroundColor Red
                Write-Host ""

                $successCount = 0
                $failCount = 0

                foreach ($packageId in $selectedPackages) {
                    Write-Host ">>> Uninstalling: " -ForegroundColor Magenta -NoNewline
                    Write-Host $packageId -ForegroundColor White

                    winget uninstall --id $packageId --accept-source-agreements

                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✓ Successfully uninstalled " -ForegroundColor Green -NoNewline
                        Write-Host $packageId -ForegroundColor White
                        $successCount++
                    }
                    else {
                        Write-Host "✗ Failed to uninstall " -ForegroundColor Red -NoNewline
                        Write-Host $packageId -ForegroundColor White
                        $failCount++
                    }
                    Write-Host ""
                }

                Write-Host ("=" * 60) -ForegroundColor Green
                Write-Host "Uninstallation Complete" -ForegroundColor Green
                Write-Host ("=" * 60) -ForegroundColor Green
                Write-Host "Success: " -ForegroundColor Green -NoNewline
                Write-Host $successCount -ForegroundColor White -NoNewline
                Write-Host " | Failed: " -ForegroundColor Red -NoNewline
                Write-Host $failCount -ForegroundColor White
            }
            catch {
                Write-Warning "Interactive selection error: $_"
                Write-Host "Installed packages:" -ForegroundColor Cyan
                $installedPackages | ForEach-Object {
                    Write-Host "  • $($_.Id)" -ForegroundColor White
                }
                Write-Host ""
                Write-Host "Use 'winget uninstall <PackageName>' to uninstall manually." -ForegroundColor Yellow
                return
            }
        }
        else {
            Write-Host "Installed packages:" -ForegroundColor Cyan
            $installedPackages | ForEach-Object {
                Write-Host "  • $($_.Id)" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "To uninstall a package: " -ForegroundColor Cyan -NoNewline
            Write-Host "winget uninstall <PackageName>" -ForegroundColor Yellow
            Write-Host "Note: Install PwshSpectreConsole for interactive package selection." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Error "Failed to get installed packages: $_"
    }
}
