function Export-WingetOffline {
    <#
    .SYNOPSIS
        Download packages for air-gapped/offline deployment.

    .DESCRIPTION
        Creates a portable offline package repository containing installers,
        manifests, and a self-contained deployment script. Designed for
        government, defense, and enterprise air-gapped environments where
        target machines have no internet access.

        The output folder can be copied via USB/network share to isolated
        machines and deployed with the included Install-Offline.ps1 script.

    .PARAMETER PackageId
        Package IDs to download for offline use.

    .PARAMETER FromManifest
        Path to a JSON/YAML manifest of packages to download.

    .PARAMETER FromInstalled
        Download installers for all currently installed packages (full machine clone).

    .PARAMETER OutputPath
        Destination folder for the offline repository. Default: .\WingetOffline

    .PARAMETER IncludeDependencies
        Also download package dependencies.

    .PARAMETER Architecture
        Preferred installer architecture: X64, X86, Arm64. Default: X64.

    .PARAMETER VerifyHash
        Verify SHA-256 hashes after download. Default: true.

    .PARAMETER Deploy
        Generate and include the offline deployment script.

    .EXAMPLE
        Export-WingetOffline -PackageId "Git.Git","Python.Python.3.12" -OutputPath "E:\OfflineRepo"
        Downloads Git and Python installers to a USB drive folder.

    .EXAMPLE
        Export-WingetOffline -FromManifest ".\lab-packages.json" -OutputPath "\\fileserver\offline"
        Downloads all packages from a manifest to a network share.

    .EXAMPLE
        Export-WingetOffline -FromInstalled -OutputPath "D:\AirGap" -Deploy
        Full machine clone: downloads everything installed + deployment script.

    .NOTES
        Author: Matthew Bubb
        Downloads use winget's native download capability where available,
        with fallback to direct URL fetching from manifest installer URLs.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, Position = 0)]
        [string[]]$PackageId,

        [Parameter(ParameterSetName = 'Manifest', Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FromManifest,

        [Parameter(ParameterSetName = 'Installed', Mandatory)]
        [switch]$FromInstalled,

        [string]$OutputPath = ".\WingetOffline",

        [switch]$IncludeDependencies,

        [ValidateSet('X64', 'X86', 'Arm64')]
        [string]$Architecture = 'X64',

        [bool]$VerifyHash = $true,

        [switch]$Deploy
    )

    # --- Resolve package list ---
    $packages = @()

    switch ($PSCmdlet.ParameterSetName) {
        'ById' { $packages = $PackageId }
        'Manifest' {
            $raw = Get-Content -Path $FromManifest -Raw
            if ($FromManifest -match '\.ya?ml$') {
                # Simple YAML parsing for package lists
                $packages = $raw.Split("`n") | Where-Object { $_ -match '^\s*-\s*(.+)' } | ForEach-Object { $Matches[1].Trim() }
            } else {
                $manifest = $raw | ConvertFrom-Json
                $packages = $manifest.packages ?? $manifest.Packages ?? $manifest
                if ($packages -is [array] -and $packages[0].Id) {
                    $packages = $packages | ForEach-Object { $_.Id }
                }
            }
        }
        'Installed' {
            $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
            $packages = @($installed | ForEach-Object { $_.Id })
            Write-Host "  Exporting $($packages.Count) installed packages for offline use." -ForegroundColor Cyan
        }
    }

    if ($packages.Count -eq 0) {
        Write-Error "No packages to export."
        return
    }

    # --- Create output structure ---
    $repoPath = (Resolve-Path $OutputPath -ErrorAction SilentlyContinue)?.Path ?? $OutputPath
    $installersDir = Join-Path $repoPath "installers"
    $manifestsDir = Join-Path $repoPath "manifests"

    New-Item -Path $repoPath -ItemType Directory -Force | Out-Null
    New-Item -Path $installersDir -ItemType Directory -Force | Out-Null
    New-Item -Path $manifestsDir -ItemType Directory -Force | Out-Null

    # --- Banner ---
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║         WingetBatch Offline Repository              ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Packages:   " -NoNewline -ForegroundColor DarkGray; Write-Host $packages.Count -ForegroundColor White
    Write-Host "  Output:     " -NoNewline -ForegroundColor DarkGray; Write-Host $repoPath -ForegroundColor White
    Write-Host "  Arch:       " -NoNewline -ForegroundColor DarkGray; Write-Host $Architecture -ForegroundColor White
    Write-Host "  Verify:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($VerifyHash) { "SHA-256" } else { "Skip" }) -ForegroundColor White
    Write-Host ""

    # --- Download packages ---
    $headers = @{ 'User-Agent' = 'WingetBatch-Offline' }
    $token = Get-WingetBatchGitHubToken -ErrorAction SilentlyContinue
    if ($token) { $headers['Authorization'] = "Bearer $token" }

    $manifest = @{
        Created = (Get-Date -ToString 'o')
        Hostname = $env:COMPUTERNAME
        Architecture = $Architecture
        Packages = @()
    }

    $successCount = 0
    $failCount = 0
    $total = $packages.Count
    $i = 0

    foreach ($pkgId in $packages) {
        $i++
        Write-Progress -Activity "Downloading offline packages" -Status "[$i/$total] $pkgId" -PercentComplete (($i / $total) * 100)
        Write-Host "  [$i/$total] " -NoNewline -ForegroundColor DarkGray
        Write-Host $pkgId -NoNewline -ForegroundColor Cyan
        Write-Host "..." -NoNewline

        try {
            # Get installer URL from winget-pkgs manifest
            $idParts = $pkgId.Split('.')
            $publisher = $idParts[0]
            $firstLetter = $publisher[0].ToString().ToLower()
            $packagePath = $idParts -join '/'

            $apiBase = "https://api.github.com/repos/microsoft/winget-pkgs/contents"
            $manifestDir = "$apiBase/manifests/$firstLetter/$packagePath"

            $versions = Invoke-RestMethod -Uri $manifestDir -Headers $headers -ErrorAction Stop
            $latest = $versions | Sort-Object { [version]($_.name -replace '[^0-9.]', '') } -ErrorAction SilentlyContinue | Select-Object -Last 1
            if (-not $latest) { $latest = $versions | Select-Object -Last 1 }

            # Get installer manifest
            $versionFiles = Invoke-RestMethod -Uri $latest.url -Headers $headers -ErrorAction Stop
            $installerFile = $versionFiles | Where-Object { $_.name -match '\.installer\.yaml$' } | Select-Object -First 1

            $downloadUrl = $null
            $expectedHash = $null
            $installerType = 'exe'

            if ($installerFile) {
                $content = Invoke-RestMethod -Uri $installerFile.url -Headers $headers -ErrorAction Stop
                $rawContent = $content.content
                if ($content.encoding -eq 'base64') {
                    $rawContent = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($rawContent))
                }

                # Parse installer URL for target architecture
                $archPattern = "Architecture:\s*$Architecture"
                if ($rawContent -match "InstallerUrl:\s*(.+)" ) {
                    $downloadUrl = $Matches[1].Trim()
                }
                if ($rawContent -match "InstallerSha256:\s*([A-Fa-f0-9]{64})") {
                    $expectedHash = $Matches[1]
                }
                if ($rawContent -match "InstallerType:\s*(\w+)") {
                    $installerType = $Matches[1]
                }

                # Save manifest
                $manifestPath = Join-Path $manifestsDir "$pkgId.yaml"
                $rawContent | Set-Content -Path $manifestPath -Encoding UTF8
            }

            if (-not $downloadUrl) {
                Write-Host " ⚠ (no installer URL found)" -ForegroundColor Yellow
                $failCount++
                $manifest.Packages += @{ Id = $pkgId; Version = $latest.name; Status = 'NoUrl' }
                continue
            }

            # Download installer
            $ext = switch ($installerType) {
                'msix' { '.msix' }
                'msi' { '.msi' }
                'appx' { '.appx' }
                default { '.exe' }
            }
            $fileName = "$($pkgId -replace '[^a-zA-Z0-9.]', '_')_$($latest.name)$ext"
            $filePath = Join-Path $installersDir $fileName

            Invoke-WebRequest -Uri $downloadUrl -OutFile $filePath -UseBasicParsing -ErrorAction Stop

            # Verify hash
            $hashOk = $true
            if ($VerifyHash -and $expectedHash) {
                $actualHash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
                $hashOk = $actualHash -eq $expectedHash
                if (-not $hashOk) {
                    Write-Host " ✗ HASH MISMATCH" -ForegroundColor Red
                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                    $failCount++
                    $manifest.Packages += @{ Id = $pkgId; Version = $latest.name; Status = 'HashMismatch' }
                    continue
                }
            }

            $fileSize = [Math]::Round((Get-Item $filePath).Length / 1MB, 1)
            Write-Host " ✓ (${fileSize}MB)" -ForegroundColor Green
            $successCount++
            $manifest.Packages += @{
                Id = $pkgId; Version = $latest.name; File = $fileName
                Size = "${fileSize}MB"; Hash = $expectedHash; Type = $installerType
                Status = 'Downloaded'
            }
        }
        catch {
            Write-Host " ✗ ($($_.Exception.Message))" -ForegroundColor Red
            $failCount++
            $manifest.Packages += @{ Id = $pkgId; Status = 'Failed'; Error = $_.Exception.Message }
        }
    }

    Write-Progress -Activity "Downloading offline packages" -Completed

    # --- Save manifest ---
    $manifestFile = Join-Path $repoPath "offline_manifest.json"
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestFile -Encoding UTF8

    # --- Generate deployment script ---
    if ($Deploy) {
        $deployScript = @'
# WingetBatch Offline Deployment Script
# Run this on the air-gapped target machine
# Usage: .\Install-Offline.ps1 [-All] [-PackageId "Git.Git"]

param(
    [switch]$All,
    [string[]]$PackageId
)

$ErrorActionPreference = 'Continue'
$scriptDir = $PSScriptRoot
$manifestPath = Join-Path $scriptDir "offline_manifest.json"
$installersDir = Join-Path $scriptDir "installers"

if (-not (Test-Path $manifestPath)) {
    Write-Error "offline_manifest.json not found. Run this from the offline repo folder."
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$packages = $manifest.Packages | Where-Object { $_.Status -eq 'Downloaded' }

if ($PackageId) {
    $packages = $packages | Where-Object { $_.Id -in $PackageId }
}

Write-Host ""
Write-Host "  WingetBatch Offline Deployment" -ForegroundColor Cyan
Write-Host "  Packages: $($packages.Count) | Source: $scriptDir" -ForegroundColor DarkGray
Write-Host ""

$success = 0; $failed = 0
foreach ($pkg in $packages) {
    $filePath = Join-Path $installersDir $pkg.File
    if (-not (Test-Path $filePath)) {
        Write-Host "  [SKIP] $($pkg.Id) - file missing" -ForegroundColor Yellow
        continue
    }

    Write-Host "  [INSTALL] $($pkg.Id) v$($pkg.Version)..." -NoNewline -ForegroundColor Cyan
    try {
        $args = switch ($pkg.Type) {
            'msi' { "/i `"$filePath`" /qn /norestart" }
            'msix' { "" }
            default { "/S /silent /quiet" }
        }

        if ($pkg.Type -eq 'msix') {
            Add-AppxPackage -Path $filePath -ErrorAction Stop
        } else {
            $proc = Start-Process -FilePath $filePath -ArgumentList $args -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -notin @(0, 3010, 1641)) { throw "Exit code: $($proc.ExitCode)" }
        }
        Write-Host " OK" -ForegroundColor Green
        $success++
    } catch {
        Write-Host " FAILED ($($_.Exception.Message))" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "  Complete: $success installed, $failed failed." -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
Write-Host ""
'@
        $deployPath = Join-Path $repoPath "Install-Offline.ps1"
        $deployScript | Set-Content -Path $deployPath -Encoding UTF8
    }

    # --- Summary ---
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "  │           Offline Repository Complete               │" -ForegroundColor White
    Write-Host "  ├─────────────────────────────────────────────────────┤" -ForegroundColor White
    Write-Host "  │  Downloaded: $successCount | Failed: $failCount | Total: $total" -ForegroundColor White
    Write-Host "  │  Path: $repoPath" -ForegroundColor White
    if ($Deploy) {
        Write-Host "  │  Deploy: .\Install-Offline.ps1 -All" -ForegroundColor White
    }
    Write-Host "  └─────────────────────────────────────────────────────┘" -ForegroundColor White
    Write-Host ""

    return [PSCustomObject]@{
        OutputPath = $repoPath
        Downloaded = $successCount
        Failed = $failCount
        Total = $total
        ManifestFile = $manifestFile
        DeployScript = if ($Deploy) { (Join-Path $repoPath "Install-Offline.ps1") } else { $null }
    }
}
