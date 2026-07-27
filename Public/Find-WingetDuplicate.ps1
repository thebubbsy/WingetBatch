function Find-WingetDuplicate {
    <#
    .SYNOPSIS
        Detect duplicate and redundant packages on the system.

    .DESCRIPTION
        Scans all installed winget packages and identifies potential duplicates:
        - Same package installed from multiple sources (winget + msstore)
        - Multiple versions of the same package family (e.g., Python 3.10 + 3.11 + 3.12)
        - Packages with overlapping functionality (same publisher, similar names)

        Helps reclaim disk space and reduce system clutter.

    .PARAMETER IncludeVersions
        Also flag multiple versions of the same package family.

    .PARAMETER ExportHtml
        Generate an HTML report of findings.

    .EXAMPLE
        Find-WingetDuplicate
        Finds packages installed from multiple sources.

    .EXAMPLE
        Find-WingetDuplicate -IncludeVersions
        Also detects multiple versions of the same package.

    .LINK
        https://github.com/thebubbsy/WingetBatch
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeVersions,

        [Parameter()]
        [switch]$ExportHtml
    )

    begin {
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch {
                Write-Error "Microsoft.WinGet.Client module is required."
                return
            }
        }
        if (-not (Get-Module -Name PwshSpectreConsole)) {
            if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
                Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
            }
        }
    }

    process {
        Write-Host ""
        Write-Host "  Scanning for duplicate packages..." -ForegroundColor Cyan

        $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
        if (-not $installed -or $installed.Count -eq 0) {
            Write-Host "  No installed packages found." -ForegroundColor Yellow
            return
        }

        Write-Host "  Analyzing $($installed.Count) installed packages..." -ForegroundColor DarkGray

        $duplicates = [System.Collections.Generic.List[PSCustomObject]]::new()
        $versionClusters = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Strategy 1: Same package ID from multiple sources
        $idGroups = $installed | Group-Object -Property Id | Where-Object { $_.Count -gt 1 }
        foreach ($group in $idGroups) {
            $sources = ($group.Group | Select-Object -ExpandProperty Source -Unique) -join ', '
            $duplicates.Add([PSCustomObject]@{
                Type       = 'Multi-Source'
                PackageId  = $group.Name
                Name       = $group.Group[0].Name
                Count      = $group.Count
                Detail     = "Installed from: $sources"
                Versions   = ($group.Group | ForEach-Object { "$($_.Source):$($_.InstalledVersion)" }) -join ', '
            })
        }

        # Strategy 2: Same name, different IDs (potential duplicates)
        $nameGroups = $installed | Where-Object { $_.Name } | Group-Object -Property Name | Where-Object { $_.Count -gt 1 }
        foreach ($group in $nameGroups) {
            $ids = ($group.Group | Select-Object -ExpandProperty Id -Unique)
            if ($ids.Count -gt 1) {
                $duplicates.Add([PSCustomObject]@{
                    Type       = 'Name Collision'
                    PackageId  = ($ids -join ', ')
                    Name       = $group.Name
                    Count      = $group.Count
                    Detail     = "Multiple IDs: $($ids -join ', ')"
                    Versions   = ($group.Group | ForEach-Object { "$($_.Id):$($_.InstalledVersion)" }) -join ', '
                })
            }
        }

        # Strategy 3: Version clusters (same package family, multiple versions)
        if ($IncludeVersions) {
            # Group by package family (e.g., Python.Python.3.x -> Python.Python)
            $familyMap = @{}
            foreach ($pkg in $installed) {
                if (-not $pkg.Id) { continue }
                # Extract family: remove last segment if it looks like a version number
                $parts = $pkg.Id -split '\.'
                $family = $pkg.Id
                if ($parts.Count -ge 3 -and $parts[-1] -match '^\d+$') {
                    $family = ($parts[0..($parts.Count - 2)]) -join '.'
                }

                if (-not $familyMap.ContainsKey($family)) {
                    $familyMap[$family] = [System.Collections.Generic.List[object]]::new()
                }
                $familyMap[$family].Add($pkg)
            }

            foreach ($family in $familyMap.Keys) {
                $members = $familyMap[$family]
                if ($members.Count -gt 1) {
                    $versions = ($members | ForEach-Object { "$($_.Id) (v$($_.InstalledVersion))" }) -join ', '
                    $versionClusters.Add([PSCustomObject]@{
                        Type       = 'Version Cluster'
                        PackageId  = $family
                        Name       = $members[0].Name
                        Count      = $members.Count
                        Detail     = $versions
                        Versions   = ($members | ForEach-Object { $_.InstalledVersion }) -join ', '
                    })
                }
            }
        }

        # Display results
        $totalFindings = $duplicates.Count + $versionClusters.Count

        Write-Host ""
        if ($totalFindings -eq 0) {
            Write-Host "  [OK] No duplicates or redundant packages detected." -ForegroundColor Green
            Write-Host ""
            return
        }

        Write-Host "  Found " -ForegroundColor White -NoNewline
        Write-Host "$totalFindings" -ForegroundColor Yellow -NoNewline
        Write-Host " potential issue(s):" -ForegroundColor White
        Write-Host ""

        # Display duplicates
        if ($duplicates.Count -gt 0) {
            Write-Host "  DUPLICATES" -ForegroundColor Red
            Write-Host "  $('─' * 56)" -ForegroundColor DarkGray

            foreach ($dup in $duplicates) {
                Write-Host "  [$($dup.Type)] " -ForegroundColor Red -NoNewline
                Write-Host $dup.Name -ForegroundColor White -NoNewline
                Write-Host " ($($dup.Count) copies)" -ForegroundColor Gray
                Write-Host "    $($dup.Detail)" -ForegroundColor DarkGray
                Write-Host ""
            }
        }

        # Display version clusters
        if ($versionClusters.Count -gt 0) {
            Write-Host "  VERSION CLUSTERS" -ForegroundColor Yellow
            Write-Host "  $('─' * 56)" -ForegroundColor DarkGray

            foreach ($cluster in $versionClusters) {
                Write-Host "  [$($cluster.Count) versions] " -ForegroundColor Yellow -NoNewline
                Write-Host $cluster.PackageId -ForegroundColor White
                Write-Host "    $($cluster.Detail)" -ForegroundColor DarkGray
                Write-Host ""
            }
        }

        # Recommendations
        Write-Host "  RECOMMENDATIONS" -ForegroundColor Cyan
        Write-Host "  $('─' * 56)" -ForegroundColor DarkGray

        if ($duplicates.Count -gt 0) {
            Write-Host "  - Remove duplicate source installs:" -ForegroundColor White
            foreach ($dup in $duplicates | Where-Object { $_.Type -eq 'Multi-Source' }) {
                Write-Host "    Uninstall-WinGetPackage -Id '$($dup.PackageId)' --Source msstore" -ForegroundColor DarkGray
            }
        }
        if ($versionClusters.Count -gt 0) {
            Write-Host "  - Consider removing old versions you no longer need:" -ForegroundColor White
            foreach ($cluster in $versionClusters) {
                Write-Host "    Review: $($cluster.Detail)" -ForegroundColor DarkGray
            }
        }
        Write-Host ""

        # HTML Export
        if ($ExportHtml) {
            $allFindings = @($duplicates) + @($versionClusters)
            $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $exportPath = Join-Path $env:TEMP "WingetBatch_Duplicates_$timestamp.html"

            try {
                Export-WingetHtmlReport -Data $allFindings -ReportTitle "Duplicate Package Analysis" -FilePath $exportPath
                if (Test-Path $exportPath) {
                    Write-Host "  [OK] Report saved: $exportPath" -ForegroundColor Green
                    Invoke-Item $exportPath
                }
            } catch {
                Write-Host "  [FAIL] Could not generate report: $_" -ForegroundColor Red
            }
        }

        # Return structured data for pipeline
        [PSCustomObject]@{
            Duplicates      = $duplicates
            VersionClusters = $versionClusters
            TotalFindings   = $totalFindings
        }
    }
}
