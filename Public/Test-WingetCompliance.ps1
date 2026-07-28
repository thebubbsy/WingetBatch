function Test-WingetCompliance {
    <#
    .SYNOPSIS
        Test machine package compliance against policy definitions.

    .DESCRIPTION
        Enterprise-lite policy enforcement for winget packages. Define required
        packages, banned packages, and version floors in a policy file, then
        test any machine for compliance. Returns structured pass/fail results
        with detailed violation reporting.

        Supports auto-remediation: install missing required packages and
        uninstall banned ones with a single switch.

    .PARAMETER PolicyPath
        Path to a policy definition file (JSON or YAML).

    .PARAMETER RequiredPackages
        Inline array of required package IDs (must be installed).

    .PARAMETER BannedPackages
        Inline array of banned package IDs (must NOT be installed).

    .PARAMETER VersionFloors
        Hashtable of package ID -> minimum version (e.g., @{'Git.Git'='2.40.0'}).

    .PARAMETER Remediate
        Automatically fix violations: install missing required, uninstall banned.

    .PARAMETER ExportReport
        Save compliance report to a JSON file.

    .PARAMETER Strict
        Fail on ANY violation (default: report all but exit 0 unless -Strict).

    .PARAMETER NewPolicy
        Generate a policy template file from current installed packages.

    .EXAMPLE
        Test-WingetCompliance -PolicyPath ".\company-policy.json"
        Tests compliance against a shared policy file.

    .EXAMPLE
        Test-WingetCompliance -RequiredPackages "Git.Git","Python.Python.3.12" -BannedPackages "TikTok.TikTok"
        Quick inline compliance check.

    .EXAMPLE
        Test-WingetCompliance -PolicyPath ".\policy.json" -Remediate
        Test and auto-fix all violations.

    .EXAMPLE
        Test-WingetCompliance -NewPolicy -PolicyPath ".\baseline-policy.json"
        Generate a policy template from current machine state.

    .NOTES
        Author: Matthew Bubb
        Policy format: JSON with 'required', 'banned', 'version_floors' arrays.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Inline')]
    param(
        [Parameter(ParameterSetName = 'File', Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$PolicyPath,

        [Parameter(ParameterSetName = 'Inline')]
        [string[]]$RequiredPackages,

        [Parameter(ParameterSetName = 'Inline')]
        [string[]]$BannedPackages,

        [Parameter(ParameterSetName = 'Inline')]
        [hashtable]$VersionFloors,

        [switch]$Remediate,

        [string]$ExportReport,

        [switch]$Strict,

        [Parameter(ParameterSetName = 'Generate', Mandatory)]
        [switch]$NewPolicy
    )

    $configDir = Get-WingetBatchConfigDir

    # --- GENERATE POLICY TEMPLATE ---
    if ($NewPolicy) {
        $packages = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
        $policy = @{
            name = "Machine Baseline Policy"
            version = "1.0"
            created = (Get-Date -ToString 'o')
            description = "Generated from $($env:COMPUTERNAME) on $(Get-Date -Format 'yyyy-MM-dd')"
            required = @($packages | ForEach-Object { $_.Id } | Sort-Object)
            banned = @()
            version_floors = @{}
        }

        $outPath = $PolicyPath ?? (Join-Path $configDir "compliance_policy.json")
        $policy | ConvertTo-Json -Depth 5 | Set-Content -Path $outPath -Encoding UTF8
        Write-Host ""
        Write-Host "  ✓ Policy template generated: $outPath" -ForegroundColor Green
        Write-Host "    $($policy.required.Count) packages marked as required." -ForegroundColor DarkGray
        Write-Host "    Edit 'banned' and 'version_floors' to customize." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # --- LOAD POLICY ---
    $required = @()
    $banned = @()
    $floors = @{}

    if ($PolicyPath) {
        $raw = Get-Content -Path $PolicyPath -Raw
        $policy = $raw | ConvertFrom-Json -AsHashtable
        $required = $policy.required ?? @()
        $banned = $policy.banned ?? @()
        $floors = $policy.version_floors ?? @{}
        $policyName = $policy.name ?? (Split-Path $PolicyPath -Leaf)
    } else {
        $required = $RequiredPackages ?? @()
        $banned = $BannedPackages ?? @()
        $floors = $VersionFloors ?? @{}
        $policyName = "Inline Policy"
    }

    if ($required.Count -eq 0 -and $banned.Count -eq 0 -and $floors.Count -eq 0) {
        Write-Host "  No policy rules defined. Nothing to check." -ForegroundColor Yellow
        return
    }

    # --- GET INSTALLED PACKAGES ---
    $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
    $installedMap = @{}
    foreach ($pkg in $installed) {
        $installedMap[$pkg.Id] = $pkg.InstalledVersion
    }

    # --- EVALUATE COMPLIANCE ---
    $violations = [System.Collections.Generic.List[hashtable]]::new()
    $compliant = [System.Collections.Generic.List[hashtable]]::new()

    # Check required
    foreach ($id in $required) {
        if ($installedMap.ContainsKey($id)) {
            $compliant.Add(@{ Rule = 'Required'; PackageId = $id; Status = 'Pass'; Detail = "Installed ($($installedMap[$id]))" })
        } else {
            $violations.Add(@{ Rule = 'Required'; PackageId = $id; Status = 'Fail'; Detail = 'Not installed'; Remediation = 'Install' })
        }
    }

    # Check banned
    foreach ($id in $banned) {
        if ($installedMap.ContainsKey($id)) {
            $violations.Add(@{ Rule = 'Banned'; PackageId = $id; Status = 'Fail'; Detail = "Installed ($($installedMap[$id])) but prohibited"; Remediation = 'Uninstall' })
        } else {
            $compliant.Add(@{ Rule = 'Banned'; PackageId = $id; Status = 'Pass'; Detail = 'Not installed (correct)' })
        }
    }

    # Check version floors
    foreach ($entry in $floors.GetEnumerator()) {
        $id = $entry.Key
        $minVersion = $entry.Value
        if (-not $installedMap.ContainsKey($id)) {
            $violations.Add(@{ Rule = 'VersionFloor'; PackageId = $id; Status = 'Fail'; Detail = "Not installed (requires >= $minVersion)"; Remediation = 'Install' })
        } else {
            $currentVer = $installedMap[$id]
            try {
                $isCompliant = [version]($currentVer -replace '[^0-9.]', '') -ge [version]($minVersion -replace '[^0-9.]', '')
            } catch {
                $isCompliant = $currentVer -ge $minVersion  # String fallback
            }
            if ($isCompliant) {
                $compliant.Add(@{ Rule = 'VersionFloor'; PackageId = $id; Status = 'Pass'; Detail = "$currentVer >= $minVersion" })
            } else {
                $violations.Add(@{ Rule = 'VersionFloor'; PackageId = $id; Status = 'Fail'; Detail = "$currentVer < $minVersion"; Remediation = 'Update' })
            }
        }
    }

    # --- OUTPUT ---
    $totalChecks = $violations.Count + $compliant.Count
    $isCompliant = $violations.Count -eq 0

    Write-Host ""
    if ($isCompliant) {
        Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║          ✓ COMPLIANT                           ║" -ForegroundColor Green
        Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Green
    } else {
        Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "  ║          ✗ NON-COMPLIANT                       ║" -ForegroundColor Red
        Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  Policy:   " -NoNewline -ForegroundColor DarkGray; Write-Host $policyName -ForegroundColor White
    Write-Host "  Checks:   " -NoNewline -ForegroundColor DarkGray; Write-Host "$totalChecks ($($compliant.Count) pass, $($violations.Count) fail)" -ForegroundColor White
    Write-Host ""

    # Show violations
    if ($violations.Count -gt 0) {
        Write-Host "  Violations:" -ForegroundColor Red
        foreach ($v in $violations) {
            $icon = switch ($v.Rule) { 'Required' { '!' }; 'Banned' { '⊘' }; 'VersionFloor' { '↑' } }
            Write-Host "    $icon " -NoNewline -ForegroundColor Red
            Write-Host "$($v.PackageId)" -NoNewline -ForegroundColor White
            Write-Host " [$($v.Rule)] " -NoNewline -ForegroundColor DarkGray
            Write-Host "— $($v.Detail)" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Show passing (verbose)
    if ($VerbosePreference -ne 'SilentlyContinue' -and $compliant.Count -gt 0) {
        Write-Host "  Passing:" -ForegroundColor Green
        foreach ($c in $compliant | Select-Object -First 20) {
            Write-Host "    ✓ $($c.PackageId) — $($c.Detail)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    # --- REMEDIATE ---
    if ($Remediate -and $violations.Count -gt 0) {
        Write-Host "  Remediating $($violations.Count) violations..." -ForegroundColor Cyan
        Write-Host ""

        foreach ($v in $violations) {
            switch ($v.Remediation) {
                'Install' {
                    Write-Host "    + Installing $($v.PackageId)..." -NoNewline -ForegroundColor Green
                    try {
                        Microsoft.WinGet.Client\Install-WinGetPackage -Id $v.PackageId -Mode Silent | Out-Null
                        Write-Host " ✓" -ForegroundColor Green
                    } catch {
                        Write-Host " ✗ ($($_.Exception.Message))" -ForegroundColor Red
                    }
                }
                'Uninstall' {
                    Write-Host "    - Uninstalling $($v.PackageId)..." -NoNewline -ForegroundColor Red
                    try {
                        Microsoft.WinGet.Client\Uninstall-WinGetPackage -Id $v.PackageId -Mode Silent | Out-Null
                        Write-Host " ✓" -ForegroundColor Green
                    } catch {
                        Write-Host " ✗ ($($_.Exception.Message))" -ForegroundColor Red
                    }
                }
                'Update' {
                    Write-Host "    ↑ Updating $($v.PackageId)..." -NoNewline -ForegroundColor Yellow
                    try {
                        Microsoft.WinGet.Client\Update-WinGetPackage -Id $v.PackageId -Mode Silent | Out-Null
                        Write-Host " ✓" -ForegroundColor Green
                    } catch {
                        Write-Host " ✗ ($($_.Exception.Message))" -ForegroundColor Red
                    }
                }
            }
        }
        Write-Host ""
        Write-Host "  Remediation complete. Re-run to verify compliance." -ForegroundColor Cyan
        Write-Host ""
    }

    # --- EXPORT ---
    if ($ExportReport) {
        $report = @{
            Timestamp = (Get-Date -ToString 'o')
            Hostname = $env:COMPUTERNAME
            Policy = $policyName
            Compliant = $isCompliant
            TotalChecks = $totalChecks
            PassCount = $compliant.Count
            FailCount = $violations.Count
            Violations = $violations
            Passing = $compliant
        }
        $report | ConvertTo-Json -Depth 5 | Set-Content -Path $ExportReport -Encoding UTF8
        Write-Host "  Report saved: $ExportReport" -ForegroundColor Green
    }

    # --- RETURN ---
    $result = [PSCustomObject]@{
        Compliant = $isCompliant
        Policy = $policyName
        TotalChecks = $totalChecks
        PassCount = $compliant.Count
        FailCount = $violations.Count
        Violations = $violations | ForEach-Object { [PSCustomObject]$_ }
    }

    if ($Strict -and -not $isCompliant) {
        Write-Error "COMPLIANCE FAILURE: $($violations.Count) violations detected (Strict mode)."
    }

    return $result
}
