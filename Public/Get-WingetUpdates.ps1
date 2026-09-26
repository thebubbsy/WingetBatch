function Get-WingetUpdates {
    <#
    .SYNOPSIS
        Check for and install available winget package updates.

    .DESCRIPTION
        Displays a list of all installed winget packages that have updates available,
        with an interactive selection to choose which ones to update.
        Uses the Microsoft.WinGet.Client COM API for reliable package enumeration.

    .PARAMETER Force
        Skip the cache and force a fresh check for updates.

    .PARAMETER ListOnly
        Return the available updates as objects without prompting or installing.
        Use this from scripts, scheduled tasks and the REST server.

    .EXAMPLE
        Get-WingetUpdates
        Shows available updates and allows you to select which to install.

    .EXAMPLE
        Get-WingetUpdates -Force
        Forces a fresh check for updates.

    .EXAMPLE
        Get-WingetUpdates -ListOnly | Where-Object Source -eq 'winget'
        Lists pending updates as objects for further processing.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$ListOnly,

        [Parameter()]
        [switch]$IWantToLiterallyUpdateAllFuckingResults,

        [Parameter()]
        [switch]$ExportHtml,

        [Parameter()]
        [ValidateSet("Default", "Silent", "Interactive")]
        [string]$Mode,

        [Parameter()]
        [ValidateSet("User", "Machine")]
        [string]$Scope,

        [Parameter()]
        [string]$Architecture,

        [Parameter()]
        [string]$Override,

        [Parameter()]
        [string]$Location,

        [Parameter()]
        [switch]$ForceInstall,

        [Parameter()]
        [switch]$SkipDependencies,

        [Parameter()]
        [switch]$AllowHashMismatch
    )

    # Ensure Microsoft.WinGet.Client is available
    if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        }
        catch {
            Write-Error "Microsoft.WinGet.Client module is required. Install it with: Install-Module Microsoft.WinGet.Client -Force"
            return
        }
    }

    if (-not $ListOnly) {
        Write-Host "Checking for winget package updates..." -ForegroundColor Cyan
    }

    # Check cache first
    $configDir = Get-WingetBatchConfigDir
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    $cacheFile = Join-Path $configDir "update_cache.json"
    $useCache = $false
    $updatesAvailable = [System.Collections.Generic.List[PSCustomObject]]::new()

    if (-not $Force -and (Test-Path $cacheFile)) {
        try {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $cacheAge = ((Get-Date) - [DateTime]::Parse($cache.LastChecked)).TotalMinutes

            # Only trust caches written in the current format (they carry AvailableVersion)
            if ($cacheAge -lt 30 -and @($cache.Updates).Count -gt 0 -and $null -ne @($cache.Updates)[0].AvailableVersion) {
                $useCache = $true
                foreach ($u in $cache.Updates) {
                    $updatesAvailable.Add([PSCustomObject]@{
                        Id = $u.Id; Name = $u.Name; InstalledVersion = $u.InstalledVersion
                        AvailableVersion = $u.AvailableVersion; Source = $u.Source
                    })
                }
                if (-not $ListOnly) {
                    Write-Host "Using cached results (checked $([Math]::Round($cacheAge, 0)) minutes ago, -Force to refresh)" -ForegroundColor DarkGray
                }
            }
        }
        catch {
            # Cache is corrupt, ignore
        }
    }

    if (-not $useCache) {
        if (-not $ListOnly) {
            Write-Host "Querying installed packages via COM API..." -ForegroundColor DarkGray
        }
        $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue

        foreach ($pkg in $installed) {
            if ($pkg.IsUpdateAvailable) {
                $updatesAvailable.Add([PSCustomObject]@{
                    Id               = $pkg.Id
                    Name             = $pkg.Name
                    InstalledVersion = $pkg.InstalledVersion
                    AvailableVersion = @($pkg.AvailableVersions)[0]
                    Source           = $pkg.Source
                })
            }
        }

        # Save to cache (also read by the profile update notification)
        try {
            $cacheData = @{
                LastChecked = (Get-Date).ToString('o')
                UpdateCount = $updatesAvailable.Count
                Updates     = @($updatesAvailable)
            } | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($cacheFile, $cacheData, [System.Text.Encoding]::UTF8)
        }
        catch {
            Write-Verbose "Failed to save update cache: $_"
        }
    }

    if ($ListOnly) {
        return $updatesAvailable.ToArray()
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

    # HTML Export
    if ($ExportHtml) {
        Write-Host "`n[HTML] Exporting HTML report..." -ForegroundColor Cyan
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $defaultPath = "C:\temp\WingetBatch_Updates_$timestamp.html"
        $exportPath = Read-Host "Enter path for HTML report [Default: $defaultPath]"
        if (-not $exportPath) { $exportPath = $defaultPath }
        if (-not $exportPath.EndsWith(".html")) { $exportPath += ".html" }

        try {
            Export-WingetHtmlReport -Data $updatesAvailable.ToArray() -ReportTitle "Updates" -FilePath $exportPath
            if (Test-Path $exportPath) {
                Write-Host "[OK] Report successfully saved to $exportPath" -ForegroundColor Green
                Invoke-Item $exportPath
            }
        } catch {
            Write-Host "[FAIL] Failed to generate HTML report: $_" -ForegroundColor Red
        }
    }

    # Interactive selection
    if ($IWantToLiterallyUpdateAllFuckingResults) {
        $selectedPackages = @($updatesAvailable)
    }
    else {
        try {
            $displayToPkg = @{}
            $displayLines = foreach ($u in $updatesAvailable) {
                $name = ConvertTo-SpectreEscaped $u.Name
                $id = ConvertTo-SpectreEscaped $u.Id
                $from = ConvertTo-SpectreEscaped ([string]$u.InstalledVersion)
                $to = ConvertTo-SpectreEscaped ([string]$u.AvailableVersion)
                $display = "$name ($id) [grey]$from[/] -> [green]$to[/]"
                if ($u.Source -and $u.Source -ne 'winget') { $display += " [magenta]$(ConvertTo-SpectreEscaped $u.Source)[/]" }
                $displayToPkg[$display] = $u
                $display
            }

            $selectedLines = Read-SpectreMultiSelection -Title "[cyan]Select packages to update (Space to toggle, Enter to confirm)[/]" `
                -Choices $displayLines `
                -PageSize 20 `
                -Color "Green"

            if (@($selectedLines).Count -eq 0) {
                Write-Host "No packages selected." -ForegroundColor Yellow
                return
            }

            $selectedPackages = @($selectedLines | ForEach-Object { $displayToPkg[$_] })
        }
        catch {
            Write-Warning "Interactive selection error: $_"
            Write-Host "Packages with updates available:" -ForegroundColor Cyan
            $updatesAvailable | ForEach-Object {
                Write-Host "  - $($_.Id) ($($_.InstalledVersion) -> $($_.AvailableVersion))" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "To update all: " -ForegroundColor Cyan -NoNewline
            Write-Host "Get-WingetUpdates -IWantToLiterallyUpdateAllFuckingResults" -ForegroundColor Yellow
            return
        }
    }

    Write-Host ""
    Write-Host "Updating " -ForegroundColor Cyan -NoNewline
    Write-Host "$($selectedPackages.Count)" -ForegroundColor White -NoNewline
    Write-Host " package(s)..." -ForegroundColor Cyan
    Write-Host ""

    $successCount = 0
    $failCount = 0
    $rebootNeeded = $false
    $failures = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Default to silent updates unless the caller chose a mode
    $installOptions = @{
        Mode = $(if ($Mode) { $Mode } else { 'Silent' })
        Scope = $Scope; Architecture = $Architecture; Override = $Override; Location = $Location
        Force = [bool]$ForceInstall; SkipDependencies = [bool]$SkipDependencies; AllowHashMismatch = [bool]$AllowHashMismatch
    }

    Invoke-WingetAutoSnapshot -Reason 'Get-WingetUpdates'

    $i = 0
    foreach ($pkg in $selectedPackages) {
        $i++
        Write-Host ">>> [$i/$($selectedPackages.Count)] Updating: " -ForegroundColor Magenta -NoNewline
        Write-Host "$($pkg.Id) " -ForegroundColor White -NoNewline
        Write-Host "$($pkg.InstalledVersion) -> $($pkg.AvailableVersion)" -ForegroundColor DarkGray

        $result = Invoke-WingetPackageAction -Action Update -Id $pkg.Id -Source $pkg.Source -Options $installOptions

        if ($result.Succeeded) {
            Write-Host "[OK] Successfully updated " -ForegroundColor Green -NoNewline
            Write-Host $pkg.Id -ForegroundColor White
            if ($result.RebootRequired) { $rebootNeeded = $true }
            $successCount++
        }
        else {
            Write-Host "[FAIL] Failed to update " -ForegroundColor Red -NoNewline
            Write-Host $pkg.Id -ForegroundColor White -NoNewline
            Write-Host " ($($result.Message))" -ForegroundColor Red
            $failures.Add($result)
            $failCount++
        }
        Write-Host ""
    }

    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "Update Complete" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "Updated: " -ForegroundColor Green -NoNewline
    Write-Host $successCount -ForegroundColor White -NoNewline
    Write-Host " | Failed: " -ForegroundColor Red -NoNewline
    Write-Host $failCount -ForegroundColor White
    foreach ($f in $failures) {
        Write-Host "  - $($f.Id): $($f.Message)" -ForegroundColor DarkGray
    }
    if ($rebootNeeded) {
        Write-Host "A restart is required to finish at least one update." -ForegroundColor Yellow
    }

    # Clear cache after updates
    if (Test-Path $cacheFile) {
        Remove-Item $cacheFile -Force
    }
}
