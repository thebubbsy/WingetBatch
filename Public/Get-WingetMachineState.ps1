function Get-WingetMachineState {
    <#
    .SYNOPSIS
        Snapshot, compare, and reconcile machine package state.

    .DESCRIPTION
        Captures a complete inventory of all winget-managed packages on the system,
        exports it as a portable state manifest, compares two states for drift detection,
        and can reconcile the current machine to match a target state (install missing,
        optionally remove extraneous packages).

        This enables "Machine-as-Code" workflows: snapshot a golden machine, then
        replicate its package set onto any other Windows machine.

    .PARAMETER Export
        Export the current machine state to a manifest file.

    .PARAMETER Path
        Path to the state manifest file (.json or .yaml).

    .PARAMETER Compare
        Compare the current machine state against a saved manifest and report drift.

    .PARAMETER Reconcile
        Install missing packages and update outdated ones to match the target manifest.

    .PARAMETER RemoveExtraneous
        When used with -Reconcile, also uninstall packages not present in the manifest.

    .PARAMETER Format
        Output format for exported manifests: JSON (default) or YAML.

    .PARAMETER IncludeVersions
        Include specific version pins in the export (default: latest).

    .PARAMETER Source
        Only include packages from a specific source (e.g., winget, msstore).

    .EXAMPLE
        Get-WingetMachineState -Export -Path ".\golden-machine.json"
        Snapshots all installed packages to a JSON manifest.

    .EXAMPLE
        Get-WingetMachineState -Export -Path ".\state.yaml" -Format YAML -IncludeVersions
        Exports with exact version pins in YAML format.

    .EXAMPLE
        Get-WingetMachineState -Compare -Path ".\golden-machine.json"
        Shows what's missing, extra, or outdated vs the golden state.

    .EXAMPLE
        Get-WingetMachineState -Reconcile -Path ".\golden-machine.json"
        Installs all missing packages and updates outdated ones.

    .EXAMPLE
        Get-WingetMachineState -Reconcile -Path ".\golden-machine.json" -RemoveExtraneous
        Full reconciliation: install missing, update outdated, remove extraneous.

    .LINK
        https://github.com/thebubbsy/WingetBatch
    #>

    [CmdletBinding(DefaultParameterSetName = 'Export')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Export')]
        [switch]$Export,

        [Parameter(Mandatory, ParameterSetName = 'Compare')]
        [switch]$Compare,

        [Parameter(Mandatory, ParameterSetName = 'Reconcile')]
        [switch]$Reconcile,

        [Parameter(Mandatory, ParameterSetName = 'Compare')]
        [Parameter(Mandatory, ParameterSetName = 'Reconcile')]
        [Parameter(Mandatory, ParameterSetName = 'Export')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(ParameterSetName = 'Reconcile')]
        [switch]$RemoveExtraneous,

        [Parameter(ParameterSetName = 'Export')]
        [ValidateSet('JSON', 'YAML')]
        [string]$Format = 'JSON',

        [Parameter(ParameterSetName = 'Export')]
        [switch]$IncludeVersions,

        [Parameter(ParameterSetName = 'Export')]
        [string]$Source
    )

    begin {
        # Ensure COM API module
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch {
                Write-Error "Microsoft.WinGet.Client module is required. Install-Module Microsoft.WinGet.Client -Force"
                return
            }
        }

        # Ensure PwshSpectreConsole for rich output
        if (-not (Get-Module -Name PwshSpectreConsole)) {
            if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
                Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
            }
        }
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'Export' { Invoke-StateExport }
            'Compare' { Invoke-StateCompare }
            'Reconcile' { Invoke-StateReconcile }
        }
    }

    end {
        function Invoke-StateExport {
            Write-Host ""
            Write-Host "  Capturing machine package state..." -ForegroundColor Cyan

            $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
            if (-not $installed) {
                Write-Error "No installed packages found via COM API."
                return
            }

            # Filter by source if specified
            if ($Source) {
                $installed = $installed | Where-Object { $_.Source -eq $Source }
            }

            $packages = [System.Collections.Generic.List[object]]::new()
            foreach ($pkg in $installed) {
                $entry = [ordered]@{
                    id = $pkg.Id
                }
                if ($IncludeVersions -and $pkg.InstalledVersion) {
                    $entry['version'] = $pkg.InstalledVersion
                } else {
                    $entry['version'] = 'latest'
                }
                if ($pkg.Source) {
                    $entry['source'] = $pkg.Source
                }
                $packages.Add([PSCustomObject]$entry)
            }

            $manifest = [ordered]@{
                _metadata = [ordered]@{
                    generator    = "WingetBatch v$((Get-Module WingetBatch).Version)"
                    created      = (Get-Date).ToString('o')
                    hostname     = $env:COMPUTERNAME
                    username     = $env:USERNAME
                    os_version   = [System.Environment]::OSVersion.VersionString
                    package_count = $packages.Count
                }
                packages = $packages
            }

            # Resolve output path
            $outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            $outDir = Split-Path $outPath -Parent
            if ($outDir -and -not (Test-Path $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            }

            if ($Format -eq 'YAML') {
                if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
                    Write-Warning "powershell-yaml module not found. Falling back to JSON."
                    $outPath = $outPath -replace '\.ya?ml$', '.json'
                    $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $outPath -Encoding utf8
                } else {
                    Import-Module powershell-yaml -ErrorAction SilentlyContinue
                    $manifest | ConvertTo-Yaml | Out-File -FilePath $outPath -Encoding utf8
                }
            } else {
                $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $outPath -Encoding utf8
            }

            Write-Host ""
            Write-Host "  [OK] " -ForegroundColor Green -NoNewline
            Write-Host "$($packages.Count) packages" -ForegroundColor White -NoNewline
            Write-Host " exported to " -ForegroundColor Green -NoNewline
            Write-Host $outPath -ForegroundColor Cyan
            Write-Host ""
        }

        function Invoke-StateCompare {
            $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            if (-not (Test-Path $manifestPath)) {
                Write-Error "State manifest not found: $manifestPath"
                return
            }

            Write-Host ""
            Write-Host "  Comparing machine state against manifest..." -ForegroundColor Cyan
            Write-Host "  Manifest: " -ForegroundColor Gray -NoNewline
            Write-Host $manifestPath -ForegroundColor White

            # Parse manifest
            $content = Get-Content -Raw -Path $manifestPath
            if ($manifestPath -match '\.ya?ml$') {
                if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
                    Write-Error "powershell-yaml module required for YAML manifests."
                    return
                }
                Import-Module powershell-yaml
                $manifest = ConvertFrom-Yaml $content
            } else {
                $manifest = $content | ConvertFrom-Json
            }

            $targetPackages = $manifest.packages
            if (-not $targetPackages) {
                Write-Error "No packages found in manifest."
                return
            }

            # Get current state
            $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
            $installedMap = @{}
            foreach ($pkg in $installed) {
                if ($pkg.Id) { $installedMap[$pkg.Id] = $pkg }
            }

            # Build target map
            $targetMap = @{}
            foreach ($pkg in $targetPackages) {
                $targetMap[$pkg.id] = $pkg
            }

            # Classify drift
            $missing = [System.Collections.Generic.List[string]]::new()
            $outdated = [System.Collections.Generic.List[PSCustomObject]]::new()
            $extraneous = [System.Collections.Generic.List[string]]::new()
            $compliant = [System.Collections.Generic.List[string]]::new()

            foreach ($target in $targetPackages) {
                $pkgId = $target.id
                if ($installedMap.ContainsKey($pkgId)) {
                    $inst = $installedMap[$pkgId]
                    if ($inst.IsUpdateAvailable) {
                        $outdated.Add([PSCustomObject]@{
                            Id = $pkgId
                            Installed = $inst.InstalledVersion
                            Available = $inst.AvailableVersion
                        })
                    } else {
                        $compliant.Add($pkgId)
                    }
                } else {
                    $missing.Add($pkgId)
                }
            }

            foreach ($instId in $installedMap.Keys) {
                if (-not $targetMap.ContainsKey($instId)) {
                    $extraneous.Add($instId)
                }
            }

            # Display results
            Write-Host ""
            Write-Host "  Drift Analysis Report" -ForegroundColor White
            Write-Host "  $('=' * 50)" -ForegroundColor DarkGray

            if ($compliant.Count -gt 0) {
                Write-Host "  [OK] Compliant: " -ForegroundColor Green -NoNewline
                Write-Host "$($compliant.Count) packages" -ForegroundColor White
            }
            if ($missing.Count -gt 0) {
                Write-Host "  [!] Missing:   " -ForegroundColor Red -NoNewline
                Write-Host "$($missing.Count) packages" -ForegroundColor White
                foreach ($m in $missing) {
                    Write-Host "       - $m" -ForegroundColor Red
                }
            }
            if ($outdated.Count -gt 0) {
                Write-Host "  [~] Outdated:  " -ForegroundColor Yellow -NoNewline
                Write-Host "$($outdated.Count) packages" -ForegroundColor White
                foreach ($o in $outdated) {
                    Write-Host "       - $($o.Id) ($($o.Installed) -> $($o.Available))" -ForegroundColor Yellow
                }
            }
            if ($extraneous.Count -gt 0) {
                Write-Host "  [+] Extraneous:" -ForegroundColor Magenta -NoNewline
                Write-Host " $($extraneous.Count) packages" -ForegroundColor White
                foreach ($e in $extraneous) {
                    Write-Host "       - $e" -ForegroundColor DarkGray
                }
            }

            Write-Host ""
            $totalDrift = $missing.Count + $outdated.Count
            if ($totalDrift -eq 0) {
                Write-Host "  [OK] Machine is fully compliant with target state." -ForegroundColor Green
            } else {
                Write-Host "  [!] Drift detected: $totalDrift package(s) need attention." -ForegroundColor Yellow
                Write-Host "      Run: Get-WingetMachineState -Reconcile -Path '$Path'" -ForegroundColor DarkGray
            }
            Write-Host ""

            # Return structured object for pipeline use
            [PSCustomObject]@{
                Compliant  = $compliant.Count
                Missing    = $missing
                Outdated   = $outdated
                Extraneous = $extraneous
                IsCompliant = ($totalDrift -eq 0)
            }
        }

        function Invoke-StateReconcile {
            $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            if (-not (Test-Path $manifestPath)) {
                Write-Error "State manifest not found: $manifestPath"
                return
            }

            Write-Host ""
            Write-Host "  Reconciling machine state to target manifest..." -ForegroundColor Cyan

            # Parse manifest
            $content = Get-Content -Raw -Path $manifestPath
            if ($manifestPath -match '\.ya?ml$') {
                if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
                    Write-Error "powershell-yaml module required for YAML manifests."
                    return
                }
                Import-Module powershell-yaml
                $manifest = ConvertFrom-Yaml $content
            } else {
                $manifest = $content | ConvertFrom-Json
            }

            $targetPackages = $manifest.packages
            if (-not $targetPackages) {
                Write-Error "No packages found in manifest."
                return
            }

            # Get current state
            $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
            $installedMap = @{}
            foreach ($pkg in $installed) {
                if ($pkg.Id) { $installedMap[$pkg.Id] = $pkg }
            }

            # Determine actions needed
            $toInstall = [System.Collections.Generic.List[PSCustomObject]]::new()
            $toUpdate = [System.Collections.Generic.List[PSCustomObject]]::new()
            $toRemove = [System.Collections.Generic.List[string]]::new()

            $targetMap = @{}
            foreach ($target in $targetPackages) {
                $pkgId = $target.id
                $targetMap[$pkgId] = $target

                if ($installedMap.ContainsKey($pkgId)) {
                    $inst = $installedMap[$pkgId]
                    if ($inst.IsUpdateAvailable) {
                        $toUpdate.Add([PSCustomObject]@{ Id = $pkgId; Version = $target.version })
                    }
                } else {
                    $toInstall.Add([PSCustomObject]@{ Id = $pkgId; Version = $target.version })
                }
            }

            if ($RemoveExtraneous) {
                foreach ($instId in $installedMap.Keys) {
                    if (-not $targetMap.ContainsKey($instId)) {
                        $toRemove.Add($instId)
                    }
                }
            }

            $totalActions = $toInstall.Count + $toUpdate.Count + $toRemove.Count
            if ($totalActions -eq 0) {
                Write-Host "  [OK] Machine is already compliant. No actions needed." -ForegroundColor Green
                return
            }

            Write-Host ""
            Write-Host "  Reconciliation Plan:" -ForegroundColor White
            if ($toInstall.Count -gt 0) { Write-Host "    Install: $($toInstall.Count) packages" -ForegroundColor Green }
            if ($toUpdate.Count -gt 0) { Write-Host "    Update:  $($toUpdate.Count) packages" -ForegroundColor Yellow }
            if ($toRemove.Count -gt 0) { Write-Host "    Remove:  $($toRemove.Count) packages" -ForegroundColor Red }
            Write-Host ""

            # Confirm
            $confirmMsg = "Proceed with reconciliation of $totalActions package(s)?"
            if (-not $PSCmdlet.ShouldContinue($confirmMsg, "WingetBatch State Reconciliation")) {
                Write-Host "  Cancelled." -ForegroundColor Yellow
                return
            }

            $successCount = 0
            $failCount = 0

            # Install missing
            foreach ($pkg in $toInstall) {
                Write-Host "  >>> Installing: " -ForegroundColor Green -NoNewline
                Write-Host $pkg.Id -ForegroundColor White
                try {
                    $installArgs = @{ Id = $pkg.Id; ErrorAction = 'Stop' }
                    if ($pkg.Version -and $pkg.Version -ne 'latest') {
                        $installArgs['Version'] = $pkg.Version
                    }
                    Microsoft.WinGet.Client\Install-WinGetPackage @installArgs | Out-Null
                    Write-Host "      [OK]" -ForegroundColor Green
                    $successCount++
                } catch {
                    Write-Host "      [FAIL] $_" -ForegroundColor Red
                    $failCount++
                }
            }

            # Update outdated
            foreach ($pkg in $toUpdate) {
                Write-Host "  >>> Updating: " -ForegroundColor Yellow -NoNewline
                Write-Host $pkg.Id -ForegroundColor White
                try {
                    Microsoft.WinGet.Client\Update-WinGetPackage -Id $pkg.Id -ErrorAction Stop | Out-Null
                    Write-Host "      [OK]" -ForegroundColor Green
                    $successCount++
                } catch {
                    Write-Host "      [FAIL] $_" -ForegroundColor Red
                    $failCount++
                }
            }

            # Remove extraneous
            foreach ($pkgId in $toRemove) {
                Write-Host "  >>> Removing: " -ForegroundColor Red -NoNewline
                Write-Host $pkgId -ForegroundColor White
                try {
                    Microsoft.WinGet.Client\Uninstall-WinGetPackage -Id $pkgId -ErrorAction Stop | Out-Null
                    Write-Host "      [OK]" -ForegroundColor Green
                    $successCount++
                } catch {
                    Write-Host "      [FAIL] $_" -ForegroundColor Red
                    $failCount++
                }
            }

            Write-Host ""
            Write-Host "  $('=' * 50)" -ForegroundColor DarkGray
            Write-Host "  Reconciliation complete: " -ForegroundColor Cyan -NoNewline
            Write-Host "$successCount succeeded" -ForegroundColor Green -NoNewline
            Write-Host ", " -ForegroundColor Gray -NoNewline
            Write-Host "$failCount failed" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })
            Write-Host ""
        }
    }
}
