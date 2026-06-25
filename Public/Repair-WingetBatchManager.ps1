function Repair-WingetBatchManager {
    <#
    .SYNOPSIS
        Diagnose and repair common winget issues.

    .DESCRIPTION
        Checks for common winget problems including:
        - winget.exe not found in PATH
        - Microsoft.WinGet.Client module not installed
        - App Installer package not registered
        Attempts automatic repair for each detected issue.

    .EXAMPLE
        Repair-WingetBatchManager
        Runs full diagnostics and attempts automatic repair.
    #>

    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "WingetBatch Diagnostic & Repair Tool" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""

    $issuesFound = 0
    $issuesFixed = 0

    # Check 1: Microsoft.WinGet.Client module
    Write-Host "[CHECK] Microsoft.WinGet.Client module..." -ForegroundColor Cyan -NoNewline
    $wingetModule = Get-Module -ListAvailable -Name Microsoft.WinGet.Client | Select-Object -First 1
    if ($wingetModule) {
        Write-Host " OK (v$($wingetModule.Version))" -ForegroundColor Green
    }
    else {
        Write-Host " MISSING" -ForegroundColor Red
        $issuesFound++
        Write-Host "  [FIX] Installing Microsoft.WinGet.Client..." -ForegroundColor Yellow
        try {
            Install-Module -Name Microsoft.WinGet.Client -Scope CurrentUser -Force -SkipPublisherCheck
            Write-Host "  [OK] Installed successfully." -ForegroundColor Green
            $issuesFixed++
        }
        catch {
            Write-Host "  [FAIL] Could not install: $_" -ForegroundColor Red
        }
    }

    # Check 2: winget.exe in PATH
    Write-Host "[CHECK] winget.exe in PATH..." -ForegroundColor Cyan -NoNewline
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host " OK ($($wingetCmd.Source))" -ForegroundColor Green
    }
    else {
        Write-Host " NOT FOUND" -ForegroundColor Red
        $issuesFound++

        # Try known locations
        $knownPaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "C:\Users\$env:USERNAME\AppData\Local\Microsoft\WindowsApps\winget.exe"
        )

        $foundPath = $knownPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($foundPath) {
            $wingetDir = Split-Path $foundPath -Parent
            Write-Host "  [FIX] Found winget at: $foundPath" -ForegroundColor Yellow
            Write-Host "  [FIX] Adding to current session PATH..." -ForegroundColor Yellow
            $env:PATH = "$wingetDir;$env:PATH"
            Write-Host "  [OK] winget.exe is now accessible in this session." -ForegroundColor Green
            Write-Host "  [NOTE] This fix is session-only. To persist, add to your system PATH:" -ForegroundColor DarkGray
            Write-Host "         $wingetDir" -ForegroundColor White
            $issuesFixed++
        }
        else {
            Write-Host "  [FIX] Attempting to re-register App Installer..." -ForegroundColor Yellow
            try {
                Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
                Write-Host "  [OK] App Installer re-registered. Restart your terminal." -ForegroundColor Green
                $issuesFixed++
            }
            catch {
                Write-Host "  [FAIL] Could not re-register App Installer: $_" -ForegroundColor Red
            }
        }
    }

    # Check 3: Repair-WinGetPackageManager
    Write-Host "[CHECK] WinGet Package Manager health..." -ForegroundColor Cyan -NoNewline
    try {
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        $version = Get-WinGetVersion -ErrorAction Stop
        Write-Host " OK (WinGet v$version)" -ForegroundColor Green
    }
    catch {
        Write-Host " DEGRADED" -ForegroundColor Yellow
        $issuesFound++
        Write-Host "  [FIX] Running Repair-WinGetPackageManager..." -ForegroundColor Yellow
        try {
            Repair-WinGetPackageManager -Force -ErrorAction Stop
            Write-Host "  [OK] Package manager repaired." -ForegroundColor Green
            $issuesFixed++
        }
        catch {
            Write-Host "  [FAIL] Repair failed: $_" -ForegroundColor Red
            Write-Host "  [TIP] Try running PowerShell as Administrator and retry." -ForegroundColor DarkGray
        }
    }

    # Check 4: COM API functional test
    Write-Host "[CHECK] COM API search functional test..." -ForegroundColor Cyan -NoNewline
    try {
        $testResult = Find-WinGetPackage -Query "Microsoft.PowerShell" -Count 1 -ErrorAction Stop
        if ($testResult) {
            Write-Host " OK (Search returned results)" -ForegroundColor Green
        }
        else {
            Write-Host " WARNING (Search returned no results)" -ForegroundColor Yellow
            $issuesFound++
        }
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        $issuesFound++
        Write-Host "  [!] COM API search is not functional: $_" -ForegroundColor Red
    }

    # Summary
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    if ($issuesFound -eq 0) {
        Write-Host "[OK] All checks passed. WingetBatch is fully operational." -ForegroundColor Green
    }
    elseif ($issuesFixed -eq $issuesFound) {
        Write-Host "[OK] Found $issuesFound issue(s), all repaired successfully." -ForegroundColor Green
        Write-Host "     You may need to restart your terminal for changes to take effect." -ForegroundColor DarkGray
    }
    else {
        Write-Host "[!] Found $issuesFound issue(s), repaired $issuesFixed." -ForegroundColor Yellow
        Write-Host "    Some issues require manual intervention (see above)." -ForegroundColor DarkGray
    }
    Write-Host ("=" * 60) -ForegroundColor Cyan
}
