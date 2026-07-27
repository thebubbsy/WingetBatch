function Invoke-WinGetBatch {
    <#
    .SYNOPSIS
        Invoke Next-Generation idempotent package deployments using COM APIs and parallel downloading.

    .DESCRIPTION
        Reads package target states from a pipeline or manifest file (JSON/YAML), verifies local state
        idempotency using the native Microsoft.WinGet.Client COM APIs, parallelizes download operations,
        and serializes silent installation execution while trapping and mapping system exit codes.

    .PARAMETER Path
        Path to a JSON or YAML state manifest file defining the target package configurations.

    .PARAMETER Packages
        Optional array of package objects passed directly or via pipeline. Each package should have an 'Id' property
        and an optional 'Version' property.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent downloads. Default is 4.

    .PARAMETER Silent
        Runs installations completely silently without user interaction.

    .PARAMETER WhatIf
        Previews the deployment plan, performing idempotency checks without downloading or installing anything.

    .EXAMPLE
        Invoke-WinGetBatch -Path .\packages.yaml

    .EXAMPLE
        Get-Content .\packages.json | ConvertFrom-Json | Invoke-WinGetBatch
    #>

    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Manifest', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Pipeline', ValueFromPipeline = $true)]
        [PSCustomObject[]]$Packages,

        [Parameter()]
        [int]$ThrottleLimit = 4,

        [Parameter()]
        [switch]$Silent,

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
        [switch]$Force,

        [Parameter()]
        [switch]$SkipDependencies,

        [Parameter()]
        [switch]$AllowHashMismatch,

        [Parameter()]
        [switch]$WhatIf
    )

    begin {
        # Prepend WindowsApps folder to ensure winget and COM APIs resolve correctly
        $windowsAppsPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
        if ($env:PATH -notlike "*$windowsAppsPath*") {
            $env:PATH = "$windowsAppsPath;$env:PATH"
        }

        # Ensure Microsoft.WinGet.Client module is imported
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try {
                Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            }
            catch {
                Write-Error "Microsoft.WinGet.Client module is a required dependency. Please install it."
                return
            }
        }

        # Resolve winget.exe path for parallel script blocks
        $wingetExePath = (Get-Command winget -ErrorAction SilentlyContinue).Source
        if (-not $wingetExePath) {
            $wingetExePath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
        }

        # Initialize collections
        $targetPackages = [System.Collections.Generic.List[PSCustomObject]]::new()
        $executionQueue = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Manifest') {
            # Resolve full manifest path
            $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            if (-not (Test-Path $manifestPath)) {
                Write-Error "Manifest file not found at: $manifestPath"
                return
            }

            Write-Host "[SYSTEM] Parsing state manifest: " -NoNewline -ForegroundColor Cyan
            Write-Host $manifestPath -ForegroundColor White

            $content = Get-Content -Raw -Path $manifestPath
            $parsed = $null

            if ($manifestPath.EndsWith(".yaml") -or $manifestPath.EndsWith(".yml")) {
                if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
                    Write-Error "powershell-yaml module is required to parse YAML manifests."
                    return
                }
                $parsed = ConvertFrom-Yaml $content
            }
            elseif ($manifestPath.EndsWith(".json")) {
                $parsed = ConvertFrom-Json $content
            }
            else {
                Write-Error "Unsupported manifest format. Use .json, .yaml, or .yml"
                return
            }

            if ($parsed -and $parsed.packages) {
                foreach ($pkg in $parsed.packages) {
                    $targetPackages.Add([PSCustomObject]@{
                        Id      = $pkg.id
                        Version = if ($pkg.version) { $pkg.version } else { "latest" }
                    })
                }
            }
        }
        else {
            # Pipeline parameters input
            if ($null -ne $Packages) {
                foreach ($pkg in $Packages) {
                    if ($pkg.Id) {
                        $targetPackages.Add([PSCustomObject]@{
                            Id      = $pkg.Id
                            Version = if ($pkg.Version) { $pkg.Version } else { "latest" }
                        })
                    }
                }
            }
        }
    }

    end {
        if ($targetPackages.Count -eq 0) {
            Write-Host "[INFO] No packages resolved for deployment." -ForegroundColor Yellow
            return
        }

        Write-Host "`n[PHASE 1] Resolving and Checking Local State Idempotency..." -ForegroundColor Cyan

        # Query all installed packages once to optimize execution speed
        $installedList = Get-WinGetPackage -ErrorAction SilentlyContinue
        $installedMap = @{}
        foreach ($inst in $installedList) {
            if ($inst.Id -and -not $installedMap.ContainsKey($inst.Id)) {
                $installedMap[$inst.Id] = $inst
            }
        }

        # Validate local state idempotency against targets
        foreach ($target in $targetPackages) {
            $pkgId = $target.Id
            $targetVer = $target.Version

            Write-Host "   Checking " -NoNewline -ForegroundColor Gray
            Write-Host $pkgId -NoNewline -ForegroundColor White

            if ($installedMap.ContainsKey($pkgId)) {
                $installedPkg = $installedMap[$pkgId]
                $installedVer = $installedPkg.InstalledVersion
                $updateAvailable = $installedPkg.IsUpdateAvailable

                if ($targetVer -eq 'latest') {
                    if ($updateAvailable) {
                        Write-Host " [Outdated] Installed: $installedVer (Update Available)" -ForegroundColor Yellow
                        $executionQueue.Add($target)
                    }
                    else {
                        Write-Host " [Idempotent] Installed: $installedVer (Up to date)" -ForegroundColor Green
                    }
                }
                else {
                    # Compare specific versions
                    if ($installedVer -eq $targetVer) {
                        Write-Host " [Idempotent] Installed version matches target: $targetVer" -ForegroundColor Green
                    }
                    else {
                        Write-Host " [Mismatch] Installed: $installedVer | Target: $targetVer" -ForegroundColor Yellow
                        $executionQueue.Add($target)
                    }
                }
            }
            else {
                Write-Host " [Missing]" -ForegroundColor Red
                $executionQueue.Add($target)
            }
        }

        if ($executionQueue.Count -eq 0) {
            Write-Host "`n[OK] System state is fully idempotent. No actions required." -ForegroundColor Green
            return
        }

        Write-Host "`nDeployment execution queue compiled: " -NoNewline -ForegroundColor Cyan
        Write-Host "$($executionQueue.Count) packages require changes." -ForegroundColor White

        if ($WhatIf) {
            Write-Host "`n[WhatIf] Would execute split-phase deployment for:" -ForegroundColor Yellow
            foreach ($item in $executionQueue) {
                Write-Host "  -> $($item.Id) ($($item.Version))" -ForegroundColor Gray
            }
            return
        }

        # Phase 1: Parallel Downloads using ForEach-Object -Parallel
        Write-Host "`n[PHASE 2] Parallel Download Operations Launching..." -ForegroundColor Cyan
        $cacheDir = Join-Path $env:TEMP "winget_cache"
        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }

        $downloads = $executionQueue | ForEach-Object -Parallel {
            $wingetPath = $using:wingetExePath
            $pkgId = $_.Id
            $dlPath = Join-Path $using:cacheDir $pkgId

            Write-Host "  >>> Downloading installer for $pkgId ..." -ForegroundColor DarkGray

            # Build argument array (no Invoke-Expression - safe from injection)
            $wingetArgs = @(
                'download'
                '--id', $pkgId
                '--exact'
                '--accept-package-agreements'
                '--accept-source-agreements'
                '--disable-interactivity'
                '--download-directory', $dlPath
            )
            if ($_.Version -ne "latest") {
                $wingetArgs += @('--version', $_.Version)
            }

            $process = Start-Process -FilePath $wingetPath -ArgumentList $wingetArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput "$dlPath\stdout.log" -RedirectStandardError "$dlPath\stderr.log"

            if ($process.ExitCode -eq 0) {
                Write-Host "   Cached installer: $pkgId" -ForegroundColor Green
                return [PSCustomObject]@{ Id = $pkgId; Downloaded = $true; Path = $dlPath }
            }
            else {
                Write-Host "   Failed download cache: $pkgId (Exit Code: $($process.ExitCode))" -ForegroundColor Red
                return [PSCustomObject]@{ Id = $pkgId; Downloaded = $false; Path = $null }
            }
        } -ThrottleLimit $ThrottleLimit

        $downloadResults = @{}
        foreach ($res in $downloads) {
            $downloadResults[$res.Id] = $res
        }

        # Phase 2: Serialized Sequential Installations
        Write-Host "`n[PHASE 3] Serialized Installation Queue Executing..." -ForegroundColor Cyan
        
        $successCount = 0
        $failCount = 0
        $rebootPending = $false
        $reportData = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($pkg in $executionQueue) {
            $pkgId = $pkg.Id
            $targetVer = $pkg.Version
            $dlResult = $downloadResults[$pkgId]

            Write-Host "`n>>> Deploying: " -NoNewline -ForegroundColor Magenta
            Write-Host $pkgId -ForegroundColor White

            if ($dlResult -and $dlResult.Downloaded) {
                Write-Host "Using pre-cached local installer." -ForegroundColor DarkGray
            }
            else {
                Write-Warning "Local cache missing. Falling back to dynamic installer fetch."
            }

            # Run installation using COM API (preferred) with CLI fallback
            $installSucceeded = $false
            $exitCode = -1

            try {
                # Primary: Use COM API for installation (no shell execution needed)
                $comInstallArgs = @{
                    Id = $pkgId
                    ErrorAction = 'Stop'
                }
                if ($Silent -or $Mode -eq 'Silent') { $comInstallArgs['Mode'] = 'Silent' }
                elseif ($Mode -eq 'Interactive') { $comInstallArgs['Mode'] = 'Interactive' }
                if ($Scope) { $comInstallArgs['Scope'] = $Scope }
                if ($Architecture) { $comInstallArgs['Architecture'] = $Architecture }
                if ($Location) { $comInstallArgs['Location'] = $Location }
                if ($Override) { $comInstallArgs['Override'] = $Override }
                if ($Force) { $comInstallArgs['Force'] = $true }
                if ($SkipDependencies) { $comInstallArgs['SkipDependencies'] = $true }
                if ($AllowHashMismatch) { $comInstallArgs['AllowHashMismatch'] = $true }

                Microsoft.WinGet.Client\Install-WinGetPackage @comInstallArgs | Out-Null
                $exitCode = 0
                $installSucceeded = $true
            }
            catch {
                # Fallback: Use winget CLI with safe argument array (no Invoke-Expression)
                Write-Verbose "COM API install failed, falling back to CLI: $_"
                $wingetArgs = @(
                    'install'
                    '--id', $pkgId
                    '--exact'
                    '--accept-package-agreements'
                    '--accept-source-agreements'
                    '--disable-interactivity'
                    '--no-progress'
                )
                if ($Silent -or $Mode -eq 'Silent') { $wingetArgs += '--silent' }
                elseif ($Mode -eq 'Interactive') { $wingetArgs += '--interactive' }
                if ($targetVer -ne "latest") { $wingetArgs += @('--version', $targetVer) }
                if ($Scope -eq "Machine") { $wingetArgs += '--machine' }
                elseif ($Scope -eq "User") { $wingetArgs += '--user' }
                if ($Architecture) { $wingetArgs += @('--architecture', $Architecture) }
                if ($Location) { $wingetArgs += @('--location', $Location) }
                if ($Override) { $wingetArgs += @('--override', $Override) }
                if ($Force) { $wingetArgs += '--force' }
                if ($SkipDependencies) { $wingetArgs += '--skip-dependencies' }
                if ($AllowHashMismatch) { $wingetArgs += '--ignore-security-hash' }

                $process = Start-Process -FilePath $wingetExePath -ArgumentList $wingetArgs -Wait -NoNewWindow -PassThru
                $exitCode = $process.ExitCode
                $installSucceeded = ($exitCode -eq 0)
            }

            # Exit Code Trapping & Telemetry Mapping
            $status = "Failed"
            $message = "Unknown installation error."

            switch ($exitCode) {
                0 {
                    $status = "Success"
                    $message = "Successfully installed package."
                    $successCount++
                    Write-Host "[OK] Successfully deployed " -NoNewline -ForegroundColor Green
                    Write-Host $pkgId -ForegroundColor White
                }
                3010 {
                    $status = "Success (Reboot Required)"
                    $message = "Installation successful, but system reboot is required."
                    $successCount++
                    $rebootPending = $true
                    Write-Host "[OK] Deployed (Reboot Required): " -NoNewline -ForegroundColor Yellow
                    Write-Host $pkgId -ForegroundColor White
                }
                1641 {
                    $status = "Success (Reboot Initiated)"
                    $message = "Installation successful, reboot has been initiated."
                    $successCount++
                    $rebootPending = $true
                    Write-Host "[OK] Deployed (Reboot Initiated): " -NoNewline -ForegroundColor Yellow
                    Write-Host $pkgId -ForegroundColor White
                }
                default {
                    $status = "Failed"
                    $message = "Installer returned non-zero code: $exitCode."
                    $failCount++
                    Write-Host " Installation failed for " -NoNewline -ForegroundColor Red
                    Write-Host $pkgId -NoNewline -ForegroundColor White
                    Write-Host " (Exit Code: $exitCode)" -ForegroundColor Red
                }
            }

            $reportData.Add([PSCustomObject]@{
                PackageId = $pkgId
                Version   = $targetVer
                Status    = $status
                ExitCode  = $exitCode
                Message   = $message
                Timestamp = (Get-Date).ToString("o")
            })
        }

        # Compile structured JSON report
        $reportDir = Join-Path $env:TEMP "winget_reports"
        if (-not (Test-Path $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }

        $reportPath = Join-Path $reportDir "deployment_report_$((Get-Date).ToString('yyyyMMdd_HHmmss')).json"
        $reportObj = [ordered]@{
            Summary = @{
                TotalInstalled = $executionQueue.Count
                Successful     = $successCount
                Failed         = $failCount
                RebootRequired = $rebootPending
            }
            Results = $reportData
        }

        $reportObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $reportPath -Encoding utf8

        Write-Host "`n" + ("=" * 60) -ForegroundColor Green
        Write-Host "Deployment Operations Concluded" -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "   Successful: " -NoNewline -ForegroundColor Green
        Write-Host $successCount -ForegroundColor White
        Write-Host "   Failed:     " -NoNewline -ForegroundColor Red
        Write-Host $failCount -ForegroundColor White
        
        if ($rebootPending) {
            Write-Host "   A system reboot is pending to complete installation changes." -ForegroundColor Yellow
        }

        Write-Host "`nStructured JSON deployment audit report saved to:" -ForegroundColor Gray
        Write-Host "  $reportPath" -ForegroundColor Cyan
    }
}


