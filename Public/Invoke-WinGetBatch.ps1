function Invoke-WinGetBatch {
    <#
    .SYNOPSIS
        Idempotent, manifest-driven package deployments using the WinGet COM API.

    .DESCRIPTION
        Reads package target states from a pipeline or manifest file (JSON/YAML), verifies local state
        idempotency using the Microsoft.WinGet.Client COM API, then installs missing packages, updates
        outdated ones and applies version pins one at a time. Each result is checked against WinGet's
        reported status and written to a JSON report in ~/.wingetbatch/reports.

    .PARAMETER Path
        Path to a JSON or YAML state manifest file defining the target package configurations.

    .PARAMETER Packages
        Optional array of package objects passed directly or via pipeline. Each package should have an 'Id' property
        and an optional 'Version' property.

    .PARAMETER ThrottleLimit
        Deprecated and ignored (kept so existing scripts keep working). WinGet downloads each installer during its install.

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
                        Source  = $pkg.source
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
                            Source  = $pkg.Source
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
        $installedList = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
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
                        $executionQueue.Add([PSCustomObject]@{ Id = $pkgId; Version = $targetVer; Operation = 'Update'; Source = $installedPkg.Source })
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
                        $executionQueue.Add([PSCustomObject]@{ Id = $pkgId; Version = $targetVer; Operation = 'Install'; Source = $installedPkg.Source })
                    }
                }
            }
            else {
                Write-Host " [Missing]" -ForegroundColor Red
                $executionQueue.Add([PSCustomObject]@{ Id = $pkgId; Version = $targetVer; Operation = 'Install'; Source = $target.Source })
            }
        }

        if ($executionQueue.Count -eq 0) {
            Write-Host "`n[OK] System state is fully idempotent. No actions required." -ForegroundColor Green
            return
        }

        Write-Host "`nDeployment execution queue compiled: " -NoNewline -ForegroundColor Cyan
        Write-Host "$($executionQueue.Count) packages require changes." -ForegroundColor White

        if ($WhatIf) {
            Write-Host "`n[WhatIf] Would deploy:" -ForegroundColor Yellow
            foreach ($item in $executionQueue) {
                Write-Host "  -> $($item.Operation) $($item.Id) ($($item.Version))" -ForegroundColor Gray
            }
            return
        }

        if ($PSBoundParameters.ContainsKey('ThrottleLimit')) {
            Write-Verbose "-ThrottleLimit is ignored: installers are fetched by WinGet during each install."
        }

        Write-Host "`n[PHASE 2] Installing (one package at a time)..." -ForegroundColor Cyan

        Invoke-WingetAutoSnapshot -Reason 'Invoke-WinGetBatch'

        $installOptions = @{
            Mode = $(if ($Silent) { 'Silent' } else { $Mode })
            Scope = $Scope; Architecture = $Architecture; Override = $Override; Location = $Location
            Force = [bool]$Force; SkipDependencies = [bool]$SkipDependencies; AllowHashMismatch = [bool]$AllowHashMismatch
        }

        $successCount = 0
        $failCount = 0
        $rebootPending = $false
        $reportData = [System.Collections.Generic.List[PSCustomObject]]::new()
        $i = 0

        foreach ($pkg in $executionQueue) {
            $i++
            Write-Host "`n>>> [$i/$($executionQueue.Count)] $($pkg.Operation): " -NoNewline -ForegroundColor Magenta
            Write-Host $pkg.Id -NoNewline -ForegroundColor White
            if ($pkg.Version -ne 'latest') { Write-Host " v$($pkg.Version)" -ForegroundColor Green } else { Write-Host "" }

            $result = Invoke-WingetPackageAction -Action $pkg.Operation -Id $pkg.Id -Version $pkg.Version -Source $pkg.Source -Options $installOptions

            if ($result.Succeeded) {
                $successCount++
                if ($result.RebootRequired) {
                    $rebootPending = $true
                    $status = "Success (Reboot Required)"
                    Write-Host "[OK] Deployed (restart required): " -NoNewline -ForegroundColor Yellow
                }
                else {
                    $status = "Success"
                    Write-Host "[OK] Deployed " -NoNewline -ForegroundColor Green
                }
                Write-Host $pkg.Id -ForegroundColor White
            }
            else {
                $failCount++
                $status = "Failed"
                Write-Host "[FAIL] " -NoNewline -ForegroundColor Red
                Write-Host $pkg.Id -NoNewline -ForegroundColor White
                Write-Host " ($($result.Message))" -ForegroundColor Red
            }

            $reportData.Add([PSCustomObject]@{
                PackageId      = $pkg.Id
                Operation      = $pkg.Operation
                Version        = $pkg.Version
                Status         = $status
                WinGetStatus   = $result.Status
                RebootRequired = $result.RebootRequired
                Message        = $(if ($result.Message) { $result.Message } else { "OK" })
                Timestamp      = (Get-Date).ToString("o")
            })
        }

        # Compile structured JSON report
        $reportDir = Join-Path (Get-WingetBatchConfigDir) "reports"
        if (-not (Test-Path $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }

        $reportPath = Join-Path $reportDir "deployment_report_$((Get-Date).ToString('yyyyMMdd_HHmmss')).json"
        $reportObj = [ordered]@{
            Summary = [ordered]@{
                Total          = $executionQueue.Count
                Successful     = $successCount
                Failed         = $failCount
                RebootRequired = $rebootPending
            }
            Results = $reportData
        }

        $reportObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $reportPath -Encoding utf8

        Write-Host ("`n" + ("=" * 60)) -ForegroundColor Green
        Write-Host "Deployment Complete" -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "   Successful: " -NoNewline -ForegroundColor Green
        Write-Host $successCount -ForegroundColor White
        Write-Host "   Failed:     " -NoNewline -ForegroundColor Red
        Write-Host $failCount -ForegroundColor White

        if ($rebootPending) {
            Write-Host "   A restart is required to finish at least one installation." -ForegroundColor Yellow
        }

        Write-Host "`nJSON deployment report saved to:" -ForegroundColor Gray
        Write-Host "  $reportPath" -ForegroundColor Cyan
    }
}
