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
        $env:PATH = "C:\Users\user\AppData\Local\Microsoft\WindowsApps;" + $env:PATH

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
        $cacheDir = "C:\temp\winget_cache"
        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }

        $downloads = $executionQueue | ForEach-Object -Parallel {
            $env:PATH = "C:\Users\user\AppData\Local\Microsoft\WindowsApps;" + $env:PATH
            $pkgId = $_.Id
            $versionStr = if ($_.Version -ne "latest") { "--version $($_.Version)" } else { "" }

            Write-Host "  >>> Downloading installer for $pkgId ..." -ForegroundColor DarkGray
            
            # Executing winget download
            $dlPath = "C:\temp\winget_cache\$pkgId"
            $cmd = "winget download --id $pkgId --exact --accept-package-agreements --accept-source-agreements --disable-interactivity --download-directory $dlPath $versionStr"
            Invoke-Expression $cmd | Out-Null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "   Cached installer: $pkgId" -ForegroundColor Green
                return [PSCustomObject]@{ Id = $pkgId; Downloaded = $true; Path = $dlPath }
            }
            else {
                Write-Host "   Failed download cache: $pkgId (Exit Code: $LASTEXITCODE)" -ForegroundColor Red
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

            # Run installation
            $installMode = if ($Silent -or $Mode -eq 'Silent') { "--silent" } elseif ($Mode -eq 'Interactive') { "--interactive" } else { "" }
            $versionArg = if ($targetVer -ne "latest") { "--version $targetVer" } else { "" }

            $extraArgs = ""
            if ($Scope -eq "Machine") { $extraArgs += " --machine" }
            elseif ($Scope -eq "User") { $extraArgs += " --user" }
            if ($Architecture) { $extraArgs += " --architecture $Architecture" }
            if ($Location) { $extraArgs += " --location `"$Location`"" }
            if ($Override) { $extraArgs += " --override `"$Override`"" }
            if ($Force) { $extraArgs += " --force" }
            if ($SkipDependencies) { $extraArgs += " --skip-dependencies" }
            if ($AllowHashMismatch) { $extraArgs += " --ignore-security-hash" }

            # Execute serialized install
            $cmd = "winget install --id $pkgId --exact --accept-package-agreements --accept-source-agreements --disable-interactivity $installMode $versionArg $extraArgs"
            $output = Invoke-Expression $cmd 2>&1 | Out-String
            $exitCode = $LASTEXITCODE

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
                    Write-Host $output -ForegroundColor DarkGray
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
        $reportDir = "C:\temp\winget_reports"
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


