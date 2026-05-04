# WingetBatch Installation Script
# One-liner installer for fresh Windows 11 installs
# Downloads and installs Winget, all required dependencies, and the WingetBatch module

param(
    [switch]$SkipWinget,
    [switch]$SkipModules,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "WingetBatch Installation Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Function to check admin rights
function Test-AdminRights {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-AdminRights)) {
    Write-Host "`n⚠ This script requires administrator privileges." -ForegroundColor Yellow
    Write-Host "Please run PowerShell as Administrator and try again.`n" -ForegroundColor Yellow
    exit 1
}

# Install Winget if not already installed
if (-not $SkipWinget) {
    Write-Host "`n[1/4] Checking Winget installation..." -ForegroundColor Cyan

    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue

    if ($wingetPath -and -not $Force) {
        Write-Host "✓ Winget is already installed at: $($wingetPath.Source)" -ForegroundColor Green
    }
    else {
        Write-Host "Installing Winget from Microsoft Store..." -ForegroundColor Yellow

        # Try Method 1: Direct GitHub download
        try {
            Write-Host "Attempting to install Winget from GitHub..." -ForegroundColor Gray

            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -ErrorAction Stop
            $downloadUrl = $releases.assets | Where-Object { $_.name -match "msixbundle" } | Select-Object -First 1 -ExpandProperty browser_download_url

            if ($downloadUrl) {
                $tempFile = Join-Path $env:TEMP "winget.msixbundle"
                Write-Host "Downloading from: $downloadUrl" -ForegroundColor Gray
                Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile -ErrorAction Stop

                Write-Host "Installing package..." -ForegroundColor Gray

                # Try to install with dependency checking
                $result = Add-AppxPackage -Path $tempFile -ErrorAction SilentlyContinue -AllUsers -ForceApplicationShutdown -ErrorVariable appxError

                if ($?) {
                    Write-Host "✓ Winget installed successfully" -ForegroundColor Green
                }
                else {
                    # If direct install fails, it might need VCLibs
                    Write-Host "Installation needs dependencies. Installing VCLibs first..." -ForegroundColor Yellow

                    # Download and install VCLibs
                    $vcLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.Desktop.appx"
                    $vcLibsFile = Join-Path $env:TEMP "Microsoft.VCLibs.x64.Desktop.appx"
                    Invoke-WebRequest -Uri $vcLibsUrl -OutFile $vcLibsFile -ErrorAction SilentlyContinue
                    Add-AppxPackage -Path $vcLibsFile -ErrorAction SilentlyContinue

                    # Try Winget installation again
                    Add-AppxPackage -Path $tempFile -ErrorAction SilentlyContinue -AllUsers -ForceApplicationShutdown
                    Remove-Item $vcLibsFile -Force -ErrorAction SilentlyContinue
                }

                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2

                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    Write-Host "✓ Winget installed successfully" -ForegroundColor Green
                }
                else {
                    Write-Host "⚠ Winget installation completed but may not be in PATH yet." -ForegroundColor Yellow
                    Write-Host "  Please close and reopen PowerShell, or manually install from Microsoft Store:" -ForegroundColor Yellow
                    Write-Host "  https://apps.microsoft.com/detail/9NBLGGH4NNS1" -ForegroundColor Cyan
                }
            }
            else {
                throw "Could not find Winget installer in GitHub releases"
            }
        }
        catch {
            Write-Host "✗ Error installing Winget from GitHub: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "`n⚠ MANUAL INSTALLATION REQUIRED" -ForegroundColor Yellow
            Write-Host "Please install Windows Package Manager manually:" -ForegroundColor Yellow
            Write-Host "  Option 1: Microsoft Store (recommended)" -ForegroundColor Cyan
            Write-Host "    https://apps.microsoft.com/detail/9NBLGGH4NNS1" -ForegroundColor Cyan
            Write-Host "  Option 2: GitHub Releases" -ForegroundColor Cyan
            Write-Host "    https://github.com/microsoft/winget-cli/releases" -ForegroundColor Cyan
            Write-Host "  Option 3: Windows 11 already has it (check 'winget' in Start Menu)" -ForegroundColor Cyan
            Write-Host "`nAfter installing, run this script again with -SkipWinget switch." -ForegroundColor Yellow
        }
    }
}

# Install required PowerShell modules
if (-not $SkipModules) {
    Write-Host "`n[2/4] Installing required PowerShell modules..." -ForegroundColor Cyan

    $modules = @(
        'PwshSpectreConsole',
        'PSWindowsUpdate',
        'ExchangeOnlineManagement'
    )

    foreach ($module in $modules) {
        Write-Host "`n  Installing: $module" -ForegroundColor Gray

        $installed = Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue

        if ($installed -and -not $Force) {
            Write-Host "  ✓ $module already installed (v$($installed.Version | Select-Object -First 1))" -ForegroundColor Green
        }
        else {
            try {
                Install-Module -Name $module -Force -AllowClobber -ErrorAction Stop -Scope CurrentUser
                Write-Host "  ✓ $module installed successfully" -ForegroundColor Green
            }
            catch {
                Write-Host "  ✗ Failed to install $module : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# Download and install WingetBatch module
Write-Host "`n[3/4] Setting up WingetBatch module..." -ForegroundColor Cyan

$moduleDir = Join-Path $PROFILE\..\..\..\Documents\PowerShell\Modules\WingetBatch
$modulePath = Join-Path $moduleDir "WingetBatch.psm1"

if ((Test-Path $modulePath) -and -not $Force) {
    Write-Host "✓ WingetBatch module already exists at: $moduleDir" -ForegroundColor Green
}
else {
    Write-Host "Downloading WingetBatch from GitHub..." -ForegroundColor Gray

    try {
        $repoUrl = "https://raw.githubusercontent.com/thebubbsy/WingetBatch/main"
        $files = @(
            "WingetBatch.psm1",
            "WingetBatch.psd1",
            "README.md"
        )

        if (-not (Test-Path $moduleDir)) {
            New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null
        }

        foreach ($file in $files) {
            $fileUrl = "$repoUrl/$file"
            $filePath = Join-Path $moduleDir $file
            Write-Host "  Downloading: $file" -ForegroundColor Gray
            Invoke-WebRequest -Uri $fileUrl -OutFile $filePath -ErrorAction SilentlyContinue
        }

        if (Test-Path $modulePath) {
            Write-Host "✓ WingetBatch module downloaded successfully" -ForegroundColor Green
        }
        else {
            Write-Host "✗ Failed to download WingetBatch module" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗ Error downloading WingetBatch: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Import and configure WingetBatch
Write-Host "`n[4/4] Importing WingetBatch module..." -ForegroundColor Cyan

try {
    Import-Module WingetBatch -Force -ErrorAction Stop
    Write-Host "✓ WingetBatch module imported successfully" -ForegroundColor Green
    Write-Host "`nAvailable commands:" -ForegroundColor Cyan
    Get-Command -Module WingetBatch | Select-Object -ExpandProperty Name | ForEach-Object { Write-Host "  • $_" -ForegroundColor Green }
}
catch {
    Write-Host "✗ Failed to import WingetBatch: $($_.Exception.Message)" -ForegroundColor Red
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nYou can now use WingetBatch commands:" -ForegroundColor Cyan
Write-Host "  • Install-WingetAll `"search term`"" -ForegroundColor Green
Write-Host "  • Get-WingetUpdates" -ForegroundColor Green
Write-Host "  • Get-WingetNewPackages -Days 7" -ForegroundColor Green
Write-Host "  • Remove-WingetRecent -Days 30" -ForegroundColor Green
Write-Host "  • Enable-WingetUpdateNotifications" -ForegroundColor Green
Write-Host "`nFor help: Get-Help Install-WingetAll -Full`n" -ForegroundColor Cyan
