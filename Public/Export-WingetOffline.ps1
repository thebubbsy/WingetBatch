function Export-WingetOffline {
    <#
    .SYNOPSIS
        Download packages for air-gapped/offline deployment.

    .DESCRIPTION
        Creates a portable offline package repository containing installers,
        manifests, and a self-contained deployment script. Designed for
        environments where target machines have no internet access.

        Installers are downloaded with WinGet's own Export-WinGetPackage, which picks
        the installer for the requested architecture, verifies its SHA-256 hash against
        the manifest, and saves the manifest next to it. The generated
        Install-Offline.ps1 reads each manifest's silent switches, so installers run
        unattended with the arguments their publisher documented.

        The output folder can be copied via USB/network share to isolated machines
        and deployed with Install-Offline.ps1 (works in Windows PowerShell 5.1 and 7).

    .PARAMETER PackageId
        Package IDs to download for offline use.

    .PARAMETER FromManifest
        Path to a JSON/YAML manifest of packages (e.g. from Get-WingetMachineState -Export).

    .PARAMETER FromInstalled
        Download installers for all currently installed winget-source packages.

    .PARAMETER OutputPath
        Destination folder for the offline repository. Default: .\WingetOffline

    .PARAMETER IncludeDependencies
        Also download package dependencies.

    .PARAMETER Architecture
        Preferred installer architecture: X64, X86, Arm64. Default: X64.

    .PARAMETER VerifyHash
        Reject installers whose hash does not match the manifest. Default: true.

    .PARAMETER Deploy
        Generate and include the offline deployment script.

    .EXAMPLE
        Export-WingetOffline -PackageId "Git.Git","Python.Python.3.13" -OutputPath "E:\OfflineRepo" -Deploy
        Downloads Git and Python installers to a USB drive folder with an install script.

    .EXAMPLE
        Export-WingetOffline -FromManifest ".\lab-packages.json" -OutputPath "\\fileserver\offline"
        Downloads all packages from a manifest to a network share.

    .EXAMPLE
        Export-WingetOffline -FromInstalled -OutputPath "D:\AirGap" -Deploy
        Full machine clone: downloads everything installed + deployment script.

    .NOTES
        Author: Matthew Bubb
        Microsoft Store (msstore) packages are skipped: offline Store downloads need an
        organizational Entra ID account.
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

    if (-not (Get-Command Microsoft.WinGet.Client\Export-WinGetPackage -ErrorAction SilentlyContinue)) {
        Write-Error "Export-WinGetPackage is not available. Update the module: Install-Module Microsoft.WinGet.Client -Force"
        return
    }

    # --- Resolve package list: objects with Id and Version ('latest' = newest) ---
    $packages = [System.Collections.Generic.List[PSCustomObject]]::new()

    switch ($PSCmdlet.ParameterSetName) {
        'ById' {
            foreach ($id in $PackageId) { $packages.Add([PSCustomObject]@{ Id = $id; Version = 'latest' }) }
        }
        'Manifest' {
            $raw = Get-Content -Path $FromManifest -Raw
            $entries = @()
            if ($FromManifest -match '\.ya?ml$') {
                if (Get-Module -ListAvailable -Name powershell-yaml) {
                    Import-Module powershell-yaml -ErrorAction Stop
                    $entries = @((ConvertFrom-Yaml $raw).packages)
                }
                else {
                    # Minimal fallback: "- id: X" or "- X" list items
                    $entries = @($raw -split "\r?\n" | Where-Object { $_ -match '^\s*-\s*(?:id:\s*)?([\w\.\-]+)\s*$' } | ForEach-Object { $Matches[1] })
                }
            }
            else {
                $manifest = $raw | ConvertFrom-Json
                $entries = if ($manifest.packages) { @($manifest.packages) } elseif ($manifest.Packages) { @($manifest.Packages) } else { @($manifest) }
            }
            foreach ($e in $entries) {
                if ($e -is [string]) { $packages.Add([PSCustomObject]@{ Id = $e; Version = 'latest' }); continue }
                $id = if ($e.id) { $e.id } else { $e.Id }
                $ver = if ($e.version) { $e.version } elseif ($e.Version) { $e.Version } else { 'latest' }
                $src = if ($e.source) { $e.source } else { $e.Source }
                if ($id -and $src -ne 'msstore') { $packages.Add([PSCustomObject]@{ Id = [string]$id; Version = [string]$ver }) }
            }
        }
        'Installed' {
            $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue | Where-Object { $_.Source -eq 'winget' }
            foreach ($p in $installed) { $packages.Add([PSCustomObject]@{ Id = $p.Id; Version = 'latest' }) }
            Write-Host "  Exporting $($packages.Count) installed winget packages for offline use." -ForegroundColor Cyan
        }
    }

    if ($packages.Count -eq 0) {
        Write-Error "No packages to export."
        return
    }

    # --- Create output structure ---
    $repoPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $installersDir = Join-Path $repoPath "installers"
    New-Item -Path $installersDir -ItemType Directory -Force | Out-Null

    # --- Banner ---
    Write-Host ""
    Write-Host "  WingetBatch Offline Repository" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Packages:   " -NoNewline -ForegroundColor DarkGray; Write-Host $packages.Count -ForegroundColor White
    Write-Host "  Output:     " -NoNewline -ForegroundColor DarkGray; Write-Host $repoPath -ForegroundColor White
    Write-Host "  Arch:       " -NoNewline -ForegroundColor DarkGray; Write-Host $Architecture -ForegroundColor White
    Write-Host "  Verify:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($VerifyHash) { "SHA-256 (enforced by WinGet)" } else { "Skip" }) -ForegroundColor White
    Write-Host ""

    $manifestEntries = [System.Collections.Generic.List[object]]::new()
    $successCount = 0
    $failCount = 0
    $total = $packages.Count
    $i = 0

    foreach ($pkg in $packages) {
        $i++
        Write-Progress -Activity "Downloading offline packages" -Status "[$i/$total] $($pkg.Id)" -PercentComplete (($i / $total) * 100)
        Write-Host "  [$i/$total] " -NoNewline -ForegroundColor DarkGray
        Write-Host $pkg.Id -NoNewline -ForegroundColor Cyan
        Write-Host "..." -NoNewline

        $safeName = $pkg.Id -replace '[^\w\.\-]', '_'
        $pkgDir = Join-Path $installersDir $safeName
        if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
        New-Item -Path $pkgDir -ItemType Directory -Force | Out-Null

        try {
            $params = @{
                Id                = $pkg.Id
                MatchOption       = 'EqualsCaseInsensitive'
                Source            = 'winget'
                DownloadDirectory = $pkgDir
                Architecture      = $Architecture
                ErrorAction       = 'Stop'
            }
            if ($pkg.Version -and $pkg.Version -ne 'latest') { $params['Version'] = $pkg.Version }
            if (-not $IncludeDependencies) { $params['SkipDependencies'] = $true }
            if (-not $VerifyHash) { $params['AllowHashMismatch'] = $true }

            $result = @(Microsoft.WinGet.Client\Export-WinGetPackage @params)[-1]
            if ($result -and [string]$result.Status -ne 'Ok') {
                throw "WinGet status: $($result.Status)"
            }

            # WinGet writes the installer plus a .yaml manifest describing it
            $yaml = Get-ChildItem $pkgDir -Filter *.yaml -File | Select-Object -First 1
            $installer = Get-ChildItem $pkgDir -File | Where-Object { $_.Extension -ne '.yaml' } | Sort-Object Length -Descending | Select-Object -First 1
            if (-not $installer) { throw "No installer was downloaded." }

            $yamlText = if ($yaml) { Get-Content $yaml.FullName -Raw } else { '' }
            $version = Get-WingetYamlValue -Yaml $yamlText -Key 'PackageVersion'
            $type = if ($yamlText -match '(?m)^\s*-?\s*InstallerType:\s*(\S+)') { $Matches[1].ToLowerInvariant() } else { $installer.Extension.TrimStart('.').ToLowerInvariant() }
            $silent = if ($yamlText -match '(?m)^\s+Silent:\s*(.+)$') { $Matches[1].Trim().Trim('"', "'") } elseif ($yamlText -match '(?m)^\s+SilentWithProgress:\s*(.+)$') { $Matches[1].Trim().Trim('"', "'") } else { $null }
            $hash = (Get-FileHash -Path $installer.FullName -Algorithm SHA256).Hash
            $sizeMb = [Math]::Round($installer.Length / 1MB, 1)

            $manifestEntries.Add([ordered]@{
                Id         = $pkg.Id
                Version    = $version
                File       = "installers/$safeName/$($installer.Name)"
                Manifest   = $(if ($yaml) { "installers/$safeName/$($yaml.Name)" } else { $null })
                Type       = $type
                SilentArgs = $silent
                Hash       = $hash
                Size       = "${sizeMb}MB"
                Status     = 'Downloaded'
            })
            Write-Host " OK v$version (${sizeMb}MB, $type)" -ForegroundColor Green
            $successCount++
        }
        catch {
            Write-Host " FAILED ($($_.Exception.Message))" -ForegroundColor Red
            $failCount++
            $manifestEntries.Add([ordered]@{ Id = $pkg.Id; Status = 'Failed'; Error = $_.Exception.Message })
            Remove-Item $pkgDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Progress -Activity "Downloading offline packages" -Completed

    # --- Save manifest ---
    $manifestFile = Join-Path $repoPath "offline_manifest.json"
    [ordered]@{
        Created      = (Get-Date).ToString('o')
        Hostname     = $env:COMPUTERNAME
        Architecture = $Architecture
        Generator    = "WingetBatch v$((Get-Module WingetBatch).Version)"
        Packages     = $manifestEntries
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestFile -Encoding UTF8

    # --- Generate deployment script (must run on Windows PowerShell 5.1 too) ---
    if ($Deploy) {
        $deployScript = @'
# WingetBatch Offline Deployment Script
# Run this on the target machine from the offline repository folder.
# Usage: .\Install-Offline.ps1 -All
#        .\Install-Offline.ps1 -PackageId Git.Git

param(
    [switch]$All,
    [string[]]$PackageId
)

$ErrorActionPreference = 'Continue'
$repo = $PSScriptRoot
$manifestPath = Join-Path $repo "offline_manifest.json"

if (-not (Test-Path $manifestPath)) {
    Write-Error "offline_manifest.json not found. Run this from the offline repo folder."
    exit 1
}
if (-not $All -and -not $PackageId) {
    Write-Host "Specify -All or -PackageId <id>." -ForegroundColor Yellow
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$packages = @($manifest.Packages | Where-Object { $_.Status -eq 'Downloaded' })
# "-File" / cmd.exe callers pass "a,b" as one string
$PackageId = @($PackageId | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($PackageId) { $packages = @($packages | Where-Object { $PackageId -contains $_.Id }) }

# Silent switches for installer technologies when the manifest has none
$defaultSilent = @{
    inno     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
    nullsoft = '/S'
    burn     = '/quiet /norestart'
    wix      = '/qn /norestart'
    msi      = '/qn /norestart'
    exe      = '/S'
}

Write-Host ""
Write-Host "  WingetBatch Offline Deployment" -ForegroundColor Cyan
Write-Host "  Packages: $($packages.Count) | Source: $repo" -ForegroundColor DarkGray
Write-Host ""

$success = 0; $failed = 0; $reboot = $false
foreach ($pkg in $packages) {
    $filePath = Join-Path $repo $pkg.File
    if (-not (Test-Path $filePath)) {
        Write-Host "  [SKIP] $($pkg.Id) - file missing" -ForegroundColor Yellow
        continue
    }
    if ((Get-FileHash -Path $filePath -Algorithm SHA256).Hash -ne $pkg.Hash) {
        Write-Host "  [SKIP] $($pkg.Id) - file hash does not match the manifest" -ForegroundColor Red
        $failed++
        continue
    }

    Write-Host "  [INSTALL] $($pkg.Id) v$($pkg.Version) ($($pkg.Type))..." -NoNewline -ForegroundColor Cyan
    $silent = if ($pkg.SilentArgs) { $pkg.SilentArgs } else { $defaultSilent[$pkg.Type] }
    try {
        $exitCode = 0
        switch -Regex ($pkg.Type) {
            '^(msix|appx)$' {
                Add-AppxPackage -Path $filePath -ErrorAction Stop
            }
            '^(msi|wix)$' {
                $argsList = "/i `"$filePath`" $silent"
                $exitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList $argsList -Wait -PassThru).ExitCode
            }
            '^(zip|portable)$' {
                $dest = Join-Path $env:LOCALAPPDATA "Programs\$($pkg.Id)"
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                if ($pkg.Type -eq 'zip') { Expand-Archive -Path $filePath -DestinationPath $dest -Force }
                else { Copy-Item -Path $filePath -Destination $dest -Force }
                Write-Host " (extracted to $dest)" -NoNewline -ForegroundColor DarkGray
            }
            default {
                $proc = if ($silent) { Start-Process -FilePath $filePath -ArgumentList $silent -Wait -PassThru } else { Start-Process -FilePath $filePath -Wait -PassThru }
                $exitCode = $proc.ExitCode
            }
        }
        if (@(0, 3010, 1641) -notcontains $exitCode) { throw "Exit code: $exitCode" }
        if ($exitCode -ne 0) { $reboot = $true }
        Write-Host " OK" -ForegroundColor Green
        $success++
    } catch {
        Write-Host " FAILED ($($_.Exception.Message))" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "  Complete: $success installed, $failed failed." -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
if ($reboot) { Write-Host "  A restart is required to finish at least one installation." -ForegroundColor Yellow }
Write-Host ""
'@
        $deployPath = Join-Path $repoPath "Install-Offline.ps1"
        $deployScript | Set-Content -Path $deployPath -Encoding UTF8
    }

    # --- Summary ---
    Write-Host ""
    Write-Host "  Offline repository complete" -ForegroundColor White
    Write-Host "  Downloaded: $successCount | Failed: $failCount | Total: $total" -ForegroundColor White
    Write-Host "  Path: $repoPath" -ForegroundColor White
    if ($Deploy) {
        Write-Host "  Deploy: .\Install-Offline.ps1 -All" -ForegroundColor White
    }
    Write-Host ""

    return [PSCustomObject]@{
        OutputPath   = $repoPath
        Downloaded   = $successCount
        Failed       = $failCount
        Total        = $total
        ManifestFile = $manifestFile
        DeployScript = if ($Deploy) { (Join-Path $repoPath "Install-Offline.ps1") } else { $null }
    }
}
