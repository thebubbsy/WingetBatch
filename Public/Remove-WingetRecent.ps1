function Remove-WingetRecent {
    <#
    .SYNOPSIS
        Uninstall recently installed winget packages.

    .DESCRIPTION
        Shows packages installed in the last X days and allows interactive selection
        of which packages to uninstall.

        Install dates come from the Windows uninstall registry. Each installed package
        (from the WinGet COM API) is matched to its registry entry by registry key for
        Add/Remove Programs entries, then by exact display name, then by a cautious
        prefix match. Packages that cannot be matched confidently are left out rather
        than guessed, because this list feeds an uninstall.

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
        [ValidateRange(1, 3650)]
        [int]$Days = 1
    )

    $plural = if ($Days -ne 1) { 's' } else { '' }
    Write-Host "Searching for packages installed in the last " -ForegroundColor Cyan -NoNewline
    Write-Host "$Days day$plural..." -ForegroundColor Yellow

    # --- Registry install dates ---
    $uninstallPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $datesByKey = @{}   # registry key name (PSChildName) -> date
    $datesByName = @{}  # DisplayName -> date (case-insensitive)
    foreach ($path in $uninstallPaths) {
        foreach ($entry in (Get-ItemProperty $path -ErrorAction SilentlyContinue)) {
            if (-not $entry.DisplayName -or -not $entry.InstallDate) { continue }
            try {
                $date = [DateTime]::ParseExact([string]$entry.InstallDate, 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture)
            }
            catch { continue }
            if (-not $datesByKey.ContainsKey($entry.PSChildName)) { $datesByKey[$entry.PSChildName] = $date }
            if (-not $datesByName.ContainsKey($entry.DisplayName)) { $datesByName[$entry.DisplayName] = $date }
        }
    }

    Write-Host "Found installation dates for $($datesByName.Count) programs" -ForegroundColor DarkGray
    Write-Host ""

    # --- Installed packages (COM API: full names, no console-width truncation, any locale) ---
    try {
        $installed = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction Stop)
    }
    catch {
        Write-Error "Failed to get installed packages: $_"
        return
    }

    $cutoffDate = (Get-Date).AddDays(-$Days).Date
    $installedPackages = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($pkg in $installed) {
        if (-not $pkg.Id) { continue }
        $installDate = $null

        # 1. ARP\<scope>\<arch>\<registry key> IDs point straight at the registry entry
        if ($pkg.Id -match '^ARP\\.+\\([^\\]+)$' -and $datesByKey.ContainsKey($Matches[1])) {
            $installDate = $datesByKey[$Matches[1]]
        }
        # 2. Exact display name
        elseif ($pkg.Name -and $datesByName.ContainsKey($pkg.Name)) {
            $installDate = $datesByName[$pkg.Name]
        }
        # 3. Registry name starts with the package name ("7-Zip" -> "7-Zip 24.08 (x64)").
        #    Short names ("Go", "Git") are skipped: too likely to hit an unrelated program.
        elseif ($pkg.Name -and $pkg.Name.Length -ge 5) {
            $candidates = @($datesByName.Keys | Where-Object { $_.StartsWith($pkg.Name, [StringComparison]::OrdinalIgnoreCase) })
            if ($candidates.Count -eq 1) { $installDate = $datesByName[$candidates[0]] }
        }

        if ($installDate -and $installDate -ge $cutoffDate) {
            $installedPackages.Add([PSCustomObject]@{
                Id          = $pkg.Id
                Name        = $pkg.Name
                Version     = $pkg.InstalledVersion
                Source      = $pkg.Source
                InstallDate = $installDate
            })
        }
    }

    if ($installedPackages.Count -eq 0) {
        Write-Warning "No packages installed in the last $Days day$plural."
        Write-Host "Note: Only packages with registry install dates can be tracked." -ForegroundColor DarkGray
        return
    }

    $installedPackages = @($installedPackages | Sort-Object -Property InstallDate -Descending)

    Write-Host "Found " -ForegroundColor Green -NoNewline
    Write-Host "$($installedPackages.Count)" -ForegroundColor White -NoNewline
    Write-Host " package(s) installed in the last $Days day$plural" -ForegroundColor Green
    Write-Host ""

    try {
        $displayToPkg = @{}
        $displayLines = foreach ($p in $installedPackages) {
            $display = "($($p.InstallDate.ToString('yyyy-MM-dd'))) $(ConvertTo-SpectreEscaped $p.Name) [grey]$(ConvertTo-SpectreEscaped $p.Id)[/]"
            $displayToPkg[$display] = $p
            $display
        }

        $selectedLines = Read-SpectreMultiSelection -Title "[red]Select packages to UNINSTALL (Space to toggle, Enter to confirm)[/]" `
            -Choices $displayLines `
            -PageSize 20 `
            -Color "Red"
    }
    catch {
        Write-Warning "Interactive selection error: $_"
        Write-Host "Recently installed packages:" -ForegroundColor Cyan
        $installedPackages | ForEach-Object {
            Write-Host "  - ($($_.InstallDate.ToString('yyyy-MM-dd'))) $($_.Name) [$($_.Id)]" -ForegroundColor White
        }
        return
    }

    if (@($selectedLines).Count -eq 0) {
        Write-Host "No packages selected." -ForegroundColor Yellow
        return
    }

    $selectedPackages = @($selectedLines | ForEach-Object { $displayToPkg[$_] })

    Write-Host ""
    Write-Host "WARNING: " -ForegroundColor Red -NoNewline
    Write-Host "You are about to UNINSTALL " -ForegroundColor Yellow -NoNewline
    Write-Host "$($selectedPackages.Count)" -ForegroundColor White -NoNewline
    Write-Host " package(s):" -ForegroundColor Yellow
    Write-Host ""
    foreach ($p in $selectedPackages) {
        Write-Host "   - " -ForegroundColor Red -NoNewline
        Write-Host "$($p.Name) ($($p.Id))" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "Type " -NoNewline -ForegroundColor Yellow
    Write-Host "YES" -NoNewline -ForegroundColor Red
    Write-Host " to confirm uninstallation, or anything else to cancel: " -NoNewline -ForegroundColor Yellow
    $confirmation = Read-Host

    if ($confirmation -cne "YES") {
        Write-Host "Uninstallation cancelled." -ForegroundColor Green
        return
    }

    Invoke-WingetAutoSnapshot -Reason 'Remove-WingetRecent'

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host "Starting Uninstallation Process" -ForegroundColor Red
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host ""

    $successCount = 0
    $failCount = 0

    foreach ($p in $selectedPackages) {
        Write-Host ">>> Uninstalling: " -ForegroundColor Magenta -NoNewline
        Write-Host $p.Id -ForegroundColor White

        $result = Invoke-WingetPackageAction -Action Uninstall -Id $p.Id -Source $p.Source

        if ($result.Succeeded) {
            Write-Host "[OK] Successfully uninstalled " -ForegroundColor Green -NoNewline
            Write-Host $p.Id -ForegroundColor White
            $successCount++
        }
        else {
            Write-Host "[FAIL] Failed to uninstall " -ForegroundColor Red -NoNewline
            Write-Host $p.Id -ForegroundColor White -NoNewline
            Write-Host " ($($result.Message))" -ForegroundColor Red
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
