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

        Only packages that come from a WinGet source (winget, msstore) are exported and
        considered for removal. Programs WinGet merely sees in Add/Remove Programs
        (drivers, runtimes, OEM tools) cannot be reinstalled from a manifest and are
        never touched unless -IncludeUnmanaged is used for export.

    .PARAMETER Export
        Export the current machine state to a manifest file.

    .PARAMETER Path
        Path to the state manifest file (.json or .yaml).

    .PARAMETER Compare
        Compare the current machine state against a saved manifest and report drift.

    .PARAMETER Reconcile
        Install missing packages and update outdated ones to match the target manifest.

    .PARAMETER RemoveExtraneous
        When used with -Reconcile, also uninstall WinGet-sourced packages not present in the manifest.

    .PARAMETER Force
        With -Reconcile, skip the confirmation prompt (for unattended use).

    .PARAMETER Format
        Output format for exported manifests: JSON (default) or YAML.

    .PARAMETER IncludeVersions
        Include specific version pins in the export (default: latest).

    .PARAMETER IncludeUnmanaged
        Also export packages that have no WinGet source (informational only; they cannot be reinstalled).

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

        [Parameter(ParameterSetName = 'Reconcile')]
        [switch]$Force,

        [Parameter(ParameterSetName = 'Export')]
        [ValidateSet('JSON', 'YAML')]
        [string]$Format = 'JSON',

        [Parameter(ParameterSetName = 'Export')]
        [switch]$IncludeVersions,

        [Parameter(ParameterSetName = 'Export')]
        [switch]$IncludeUnmanaged,

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

        # --- Helpers (defined here so they exist before process{} calls them) ---

        function Read-StateManifest {
            param([string]$ManifestPath)

            if (-not (Test-Path $ManifestPath)) {
                throw "State manifest not found: $ManifestPath"
            }
            $content = Get-Content -Raw -Path $ManifestPath
            if ($ManifestPath -match '\.ya?ml$') {
                if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
                    throw "powershell-yaml module required for YAML manifests (Install-Module powershell-yaml)."
                }
                Import-Module powershell-yaml -ErrorAction Stop
                $manifest = ConvertFrom-Yaml $content
            }
            else {
                $manifest = $content | ConvertFrom-Json
            }

            $targets = foreach ($pkg in @($manifest.packages)) {
                if (-not $pkg) { continue }
                $id = if ($pkg -is [string]) { $pkg } else { [string]$pkg.id }
                if (-not $id) { continue }
                $ver = if ($pkg -isnot [string] -and $pkg.version) { [string]$pkg.version } else { 'latest' }
                $src = if ($pkg -isnot [string] -and $pkg.source) { [string]$pkg.source } else { $null }
                [PSCustomObject]@{ Id = $id; Version = $ver; Source = $src }
            }
            if (-not $targets) { throw "No packages found in manifest: $ManifestPath" }
            return @($targets)
        }

        function Get-InstalledMap {
            $map = @{}
            foreach ($pkg in (Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue)) {
                if ($pkg.Id -and -not $map.ContainsKey($pkg.Id)) { $map[$pkg.Id] = $pkg }
            }
            return $map
        }

        # Returns the drift between a target list and the installed map
        function Get-StateDrift {
            param($Targets, [hashtable]$InstalledMap)

            $missing = [System.Collections.Generic.List[PSCustomObject]]::new()
            $outdated = [System.Collections.Generic.List[PSCustomObject]]::new()
            $compliant = [System.Collections.Generic.List[string]]::new()
            $unmanageable = [System.Collections.Generic.List[string]]::new()
            $targetIds = @{}

            foreach ($t in $Targets) {
                $targetIds[$t.Id] = $true
                if ($InstalledMap.ContainsKey($t.Id)) {
                    $inst = $InstalledMap[$t.Id]
                    if ($t.Version -ne 'latest') {
                        # Pinned: compliant only when exactly that version is installed
                        if ((Compare-WingetVersion -ReferenceVersion $inst.InstalledVersion -DifferenceVersion $t.Version) -eq 0) {
                            $compliant.Add($t.Id)
                        }
                        else {
                            $outdated.Add([PSCustomObject]@{ Id = $t.Id; Installed = $inst.InstalledVersion; Target = $t.Version; Pinned = $true; Source = $inst.Source })
                        }
                    }
                    elseif ($inst.IsUpdateAvailable) {
                        $outdated.Add([PSCustomObject]@{ Id = $t.Id; Installed = $inst.InstalledVersion; Target = @($inst.AvailableVersions)[0]; Pinned = $false; Source = $inst.Source })
                    }
                    else {
                        $compliant.Add($t.Id)
                    }
                }
                elseif ($t.Id -match '^(ARP|MSIX)\\') {
                    # Add/Remove Programs entries from old exports cannot be installed by WinGet
                    $unmanageable.Add($t.Id)
                }
                else {
                    $missing.Add($t)
                }
            }

            # Extraneous = WinGet-sourced packages not in the manifest. Unsourced entries are ignored.
            $extraneous = [System.Collections.Generic.List[string]]::new()
            foreach ($id in $InstalledMap.Keys) {
                if (-not $targetIds.ContainsKey($id) -and $InstalledMap[$id].Source) {
                    $extraneous.Add($id)
                }
            }

            [PSCustomObject]@{
                Missing      = $missing
                Outdated     = $outdated
                Compliant    = $compliant
                Extraneous   = @($extraneous | Sort-Object)
                Unmanageable = $unmanageable
            }
        }

        function Invoke-StateExport {
            Write-Host ""
            Write-Host "  Capturing machine package state..." -ForegroundColor Cyan

            $installed = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue)
            if ($installed.Count -eq 0) {
                Write-Error "No installed packages found via COM API."
                return
            }

            $skipped = 0
            if (-not $IncludeUnmanaged) {
                $managed = @($installed | Where-Object { $_.Source })
                $skipped = $installed.Count - $managed.Count
                $installed = $managed
            }
            if ($Source) {
                $installed = @($installed | Where-Object { $_.Source -eq $Source })
            }

            $packages = [System.Collections.Generic.List[object]]::new()
            foreach ($pkg in ($installed | Sort-Object Id)) {
                $entry = [ordered]@{ id = $pkg.Id }
                $entry['version'] = if ($IncludeVersions -and $pkg.InstalledVersion) { $pkg.InstalledVersion } else { 'latest' }
                if ($pkg.Source) { $entry['source'] = $pkg.Source }
                $packages.Add([PSCustomObject]$entry)
            }

            $manifest = [ordered]@{
                _metadata = [ordered]@{
                    generator     = "WingetBatch v$((Get-Module WingetBatch).Version)"
                    created       = (Get-Date).ToString('o')
                    hostname      = $env:COMPUTERNAME
                    username      = $env:USERNAME
                    os_version    = [System.Environment]::OSVersion.VersionString
                    package_count = $packages.Count
                }
                packages = $packages
            }

            $outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            $outDir = Split-Path $outPath -Parent
            if ($outDir -and -not (Test-Path $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            }

            if ($Format -eq 'YAML' -and -not (Get-Module -ListAvailable -Name powershell-yaml)) {
                Write-Warning "powershell-yaml module not found. Falling back to JSON."
                $outPath = $outPath -replace '\.ya?ml$', '.json'
                $Format = 'JSON'
            }
            if ($Format -eq 'YAML') {
                Import-Module powershell-yaml -ErrorAction Stop
                $manifest | ConvertTo-Yaml | Out-File -FilePath $outPath -Encoding utf8
            }
            else {
                $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $outPath -Encoding utf8
            }

            Write-Host ""
            Write-Host "  [OK] " -ForegroundColor Green -NoNewline
            Write-Host "$($packages.Count) packages" -ForegroundColor White -NoNewline
            Write-Host " exported to " -ForegroundColor Green -NoNewline
            Write-Host $outPath -ForegroundColor Cyan
            if ($skipped -gt 0) {
                Write-Host "  Skipped $skipped programs with no WinGet source (use -IncludeUnmanaged to list them)." -ForegroundColor DarkGray
            }
            Write-Host ""
        }

        function Invoke-StateCompare {
            $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            try { $targets = Read-StateManifest -ManifestPath $manifestPath }
            catch { Write-Error $_.Exception.Message; return }

            Write-Host ""
            Write-Host "  Comparing machine state against manifest..." -ForegroundColor Cyan
            Write-Host "  Manifest: " -ForegroundColor Gray -NoNewline
            Write-Host $manifestPath -ForegroundColor White

            $drift = Get-StateDrift -Targets $targets -InstalledMap (Get-InstalledMap)

            Write-Host ""
            Write-Host "  Drift Analysis Report" -ForegroundColor White
            Write-Host "  $('=' * 50)" -ForegroundColor DarkGray

            if ($drift.Compliant.Count -gt 0) {
                Write-Host "  [OK] Compliant: " -ForegroundColor Green -NoNewline
                Write-Host "$($drift.Compliant.Count) packages" -ForegroundColor White
            }
            if ($drift.Missing.Count -gt 0) {
                Write-Host "  [!] Missing:   " -ForegroundColor Red -NoNewline
                Write-Host "$($drift.Missing.Count) packages" -ForegroundColor White
                foreach ($m in $drift.Missing) {
                    $v = if ($m.Version -ne 'latest') { " (v$($m.Version))" } else { '' }
                    Write-Host "       - $($m.Id)$v" -ForegroundColor Red
                }
            }
            if ($drift.Outdated.Count -gt 0) {
                Write-Host "  [~] Outdated:  " -ForegroundColor Yellow -NoNewline
                Write-Host "$($drift.Outdated.Count) packages" -ForegroundColor White
                foreach ($o in $drift.Outdated) {
                    $pin = if ($o.Pinned) { ' (pinned)' } else { '' }
                    Write-Host "       - $($o.Id) ($($o.Installed) -> $($o.Target))$pin" -ForegroundColor Yellow
                }
            }
            if ($drift.Extraneous.Count -gt 0) {
                Write-Host "  [+] Extraneous:" -ForegroundColor Magenta -NoNewline
                Write-Host " $($drift.Extraneous.Count) packages" -ForegroundColor White
                foreach ($e in $drift.Extraneous) {
                    Write-Host "       - $e" -ForegroundColor DarkGray
                }
            }
            if ($drift.Unmanageable.Count -gt 0) {
                Write-Host "  [-] Skipped:   $($drift.Unmanageable.Count) manifest entries have no WinGet source and cannot be installed" -ForegroundColor DarkGray
            }

            Write-Host ""
            $totalDrift = $drift.Missing.Count + $drift.Outdated.Count
            if ($totalDrift -eq 0) {
                Write-Host "  [OK] Machine is fully compliant with target state." -ForegroundColor Green
            }
            else {
                Write-Host "  [!] Drift detected: $totalDrift package(s) need attention." -ForegroundColor Yellow
                Write-Host "      Run: Get-WingetMachineState -Reconcile -Path '$Path'" -ForegroundColor DarkGray
            }
            Write-Host ""

            # Return structured object for pipeline use
            [PSCustomObject]@{
                Compliant   = $drift.Compliant.Count
                Missing     = @($drift.Missing | ForEach-Object { $_.Id })
                Outdated    = $drift.Outdated
                Extraneous  = $drift.Extraneous
                IsCompliant = ($totalDrift -eq 0)
            }
        }

        function Invoke-StateReconcile {
            $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            try { $targets = Read-StateManifest -ManifestPath $manifestPath }
            catch { Write-Error $_.Exception.Message; return }

            Write-Host ""
            Write-Host "  Reconciling machine state to target manifest..." -ForegroundColor Cyan

            $drift = Get-StateDrift -Targets $targets -InstalledMap (Get-InstalledMap)
            $toRemove = if ($RemoveExtraneous) { $drift.Extraneous } else { @() }

            $totalActions = $drift.Missing.Count + $drift.Outdated.Count + $toRemove.Count
            if ($totalActions -eq 0) {
                Write-Host "  [OK] Machine is already compliant. No actions needed." -ForegroundColor Green
                return
            }

            Write-Host ""
            Write-Host "  Reconciliation Plan:" -ForegroundColor White
            foreach ($m in $drift.Missing) { Write-Host "    + install  $($m.Id)$(if ($m.Version -ne 'latest') { " v$($m.Version)" })" -ForegroundColor Green }
            foreach ($o in $drift.Outdated) { Write-Host "    ~ $(if ($o.Pinned) { 'pin    ' } else { 'update ' }) $($o.Id) $($o.Installed) -> $($o.Target)" -ForegroundColor Yellow }
            foreach ($r in $toRemove) { Write-Host "    - remove   $r" -ForegroundColor Red }
            Write-Host ""

            if (-not $Force) {
                $confirmMsg = "Proceed with reconciliation of $totalActions package(s)?"
                if (-not $PSCmdlet.ShouldContinue($confirmMsg, "WingetBatch State Reconciliation")) {
                    Write-Host "  Cancelled." -ForegroundColor Yellow
                    return
                }
            }

            Invoke-WingetAutoSnapshot -Reason 'Get-WingetMachineState -Reconcile'

            $successCount = 0
            $failCount = 0
            $report = {
                param($result)
                if ($result.Succeeded) {
                    Write-Host "      [OK]" -ForegroundColor Green
                    return $true
                }
                Write-Host "      [FAIL] $($result.Message)" -ForegroundColor Red
                return $false
            }

            foreach ($pkg in $drift.Missing) {
                Write-Host "  >>> Installing: " -ForegroundColor Green -NoNewline
                Write-Host $pkg.Id -ForegroundColor White
                $r = Invoke-WingetPackageAction -Action Install -Id $pkg.Id -Version $pkg.Version -Source $pkg.Source -Options @{ Mode = 'Silent' }
                if (& $report $r) { $successCount++ } else { $failCount++ }
            }

            foreach ($pkg in $drift.Outdated) {
                Write-Host "  >>> $(if ($pkg.Pinned) { 'Pinning' } else { 'Updating' }): " -ForegroundColor Yellow -NoNewline
                Write-Host "$($pkg.Id) -> $($pkg.Target)" -ForegroundColor White
                if ($pkg.Pinned) {
                    # Verified move to an exact (possibly older) version
                    $r = Set-WingetPackageVersion -Id $pkg.Id -Version $pkg.Target -Source $pkg.Source
                }
                else {
                    $r = Invoke-WingetPackageAction -Action Update -Id $pkg.Id -Source $pkg.Source -Options @{ Mode = 'Silent' }
                }
                if (& $report $r) { $successCount++ } else { $failCount++ }
            }

            foreach ($pkgId in $toRemove) {
                Write-Host "  >>> Removing: " -ForegroundColor Red -NoNewline
                Write-Host $pkgId -ForegroundColor White
                $r = Invoke-WingetPackageAction -Action Uninstall -Id $pkgId -Options @{ Mode = 'Silent' }
                if (& $report $r) { $successCount++ } else { $failCount++ }
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

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'Export' { Invoke-StateExport }
            'Compare' { Invoke-StateCompare }
            'Reconcile' { Invoke-StateReconcile }
        }
    }
}
