function Get-WingetHealthScore {
    <#
    .SYNOPSIS
        Rate package trustworthiness and maintenance health.

    .DESCRIPTION
        Analyzes a package across multiple health dimensions and produces a
        composite 0-100 score with letter grade (A+ through F). Checks:

        - Freshness: How recently was the package updated in winget-pkgs?
        - Publisher Activity: Is the publisher's GitHub repo active?
        - Version Maturity: Stable releases vs pre-release/alpha/beta
        - Manifest Quality: Complete metadata (license, homepage, description)
        - Update Cadence: Regular updates vs abandoned
        - Source Trust: Official source vs third-party

        Answers the question: "Should I trust this package?"

    .PARAMETER PackageId
        One or more package IDs to analyze.

    .PARAMETER AllInstalled
        Score all installed packages (batch audit).

    .PARAMETER MinScore
        Only show packages below this score (for auditing).

    .PARAMETER Detailed
        Show full breakdown of each scoring dimension.

    .PARAMETER ExportReport
        Save health report to JSON.

    .EXAMPLE
        Get-WingetHealthScore -PackageId "Git.Git"
        Shows health score and grade for Git.

    .EXAMPLE
        Get-WingetHealthScore -PackageId "SomeObscure.Tool" -Detailed
        Full breakdown of why a package scored low.

    .EXAMPLE
        Get-WingetHealthScore -AllInstalled -MinScore 50
        Audit: show all installed packages scoring below 50.

    .NOTES
        Author: Matthew Bubb
        Scores are heuristic-based using public GitHub/winget-pkgs data.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, Position = 0, ValueFromPipeline)]
        [string[]]$PackageId,

        [Parameter(ParameterSetName = 'AllInstalled', Mandatory)]
        [switch]$AllInstalled,

        [ValidateRange(0, 100)]
        [int]$MinScore = 100,

        [switch]$Detailed,

        [string]$ExportReport
    )

    begin {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        function Get-SingleHealthScore {
            param([string]$Id)

            $score = @{
                Freshness = 0       # 0-25: How recently updated
                PublisherActivity = 0  # 0-20: GitHub activity
                VersionMaturity = 0    # 0-20: Stable vs pre-release
                ManifestQuality = 0    # 0-20: Metadata completeness
                UpdateCadence = 0      # 0-15: Regular update pattern
            }
            $details = @{
                LastModified = $null
                LatestVersion = $null
                PublisherRepo = $null
                VersionCount = 0
                HasLicense = $false
                HasHomepage = $false
                HasDescription = $false
                IsPreRelease = $false
                SourceTrust = 'Unknown'
            }

            # --- Fetch manifest data from GitHub ---
            try {
                $versions = @(Get-WingetPkgsVersions -PackageId $Id)
                if ($versions.Count -eq 0) { throw "No versions found" }
                $details.VersionCount = $versions.Count
                $latestVersion = $versions[0].Name
                $details.LatestVersion = $latestVersion

                # FRESHNESS: date of the most recent commit touching this package
                $path = Get-WingetPkgsPackagePath -PackageId $Id
                $commits = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-pkgs/commits?path=$path&per_page=1" -Headers (Get-WingetPkgsHeaders) -ErrorAction SilentlyContinue
                Update-GitHubApiRequestCount -RequestCount 1 | Out-Null
                if ($commits -and $commits[0].commit.committer.date) {
                    $details.LastModified = [datetime]$commits[0].commit.committer.date
                    $age = ((Get-Date) - $details.LastModified).TotalDays
                    $score.Freshness = if ($age -le 30) { 25 } elseif ($age -le 90) { 20 } elseif ($age -le 180) { 15 } elseif ($age -le 365) { 10 } elseif ($age -le 730) { 5 } else { 2 }
                }
                else {
                    $score.Freshness = 10  # unknown: neutral
                }

                # MANIFEST QUALITY: the descriptive fields live in the locale manifest
                $manifest = Get-WingetPkgsManifest -PackageId $Id -Version $latestVersion
                $locale = $manifest.Locale
                $details.HasLicense = [bool](Get-WingetYamlValue -Yaml $locale -Key 'License')
                $details.HasHomepage = [bool]((Get-WingetYamlValue -Yaml $locale -Key 'PackageUrl') -or (Get-WingetYamlValue -Yaml $locale -Key 'PublisherUrl'))
                $details.HasDescription = [bool]((Get-WingetYamlValue -Yaml $locale -Key 'ShortDescription') -or (Get-WingetYamlValue -Yaml $locale -Key 'Description'))
                $details.PublisherRepo = Get-WingetYamlValue -Yaml $locale -Key 'PublisherUrl'
                if (-not $details.PublisherRepo) { $details.PublisherRepo = Get-WingetYamlValue -Yaml $locale -Key 'PackageUrl' }

                $qualityScore = 0
                if ($details.HasLicense) { $qualityScore += 7 }
                if ($details.HasHomepage) { $qualityScore += 7 }
                if ($details.HasDescription) { $qualityScore += 6 }
                $score.ManifestQuality = $qualityScore

                # VERSION MATURITY: judge the version string and package ID only
                # (searching the whole manifest matched words like "Source")
                $details.IsPreRelease = ($latestVersion -match '(?i)(alpha|beta|preview|nightly|canary|insider|dev|\brc\d*\b|-rc)') -or
                                        ($Id -match '(?i)\.(Preview|Beta|Nightly|Canary|Insiders?|Dev)$')
                if ($details.IsPreRelease) {
                    $score.VersionMaturity = 8
                } elseif ((Compare-WingetVersion -ReferenceVersion $latestVersion -DifferenceVersion '1.0') -lt 0) {
                    $score.VersionMaturity = 12  # 0.x releases
                } elseif ($versions.Count -ge 3) {
                    $score.VersionMaturity = 20
                } else {
                    $score.VersionMaturity = 15
                }

                # UPDATE CADENCE: how many releases have been published to winget
                if ($versions.Count -ge 30) { $score.UpdateCadence = 15 }
                elseif ($versions.Count -ge 15) { $score.UpdateCadence = 12 }
                elseif ($versions.Count -ge 5) { $score.UpdateCadence = 9 }
                elseif ($versions.Count -ge 2) { $score.UpdateCadence = 6 }
                else { $score.UpdateCadence = 3 }

                # PUBLISHER ACTIVITY: recent commit + sustained release history
                $activity = 0
                if ($details.LastModified -and ((Get-Date) - $details.LastModified).TotalDays -le 180) { $activity += 10 }
                elseif ($details.LastModified -and ((Get-Date) - $details.LastModified).TotalDays -le 365) { $activity += 5 }
                if ($versions.Count -ge 10) { $activity += 10 } elseif ($versions.Count -ge 3) { $activity += 5 }
                $score.PublisherActivity = $activity

                $details.SourceTrust = 'winget-pkgs (community repository)'
            }
            catch {
                $status = [int]$_.Exception.Response.StatusCode
                if ($status -in 403, 429) {
                    Write-Warning "GitHub rate limit reached while scoring $Id. Run New-WingetBatchGitHubToken for 5,000 requests/hour."
                    $details.SourceTrust = 'Unknown (rate limited)'
                }
                else {
                    # Package not found on GitHub - low trust
                    $details.SourceTrust = 'Not found in winget-pkgs'
                }
                $score.Freshness = 3
                $score.PublisherActivity = 3
                $score.VersionMaturity = 5
                $score.ManifestQuality = 3
                $score.UpdateCadence = 2
            }
            # --- Composite Score ---
            $total = $score.Freshness + $score.PublisherActivity + $score.VersionMaturity + $score.ManifestQuality + $score.UpdateCadence

            # Letter grade
            $grade = if ($total -ge 90) { 'A+' }
                     elseif ($total -ge 80) { 'A' }
                     elseif ($total -ge 70) { 'B' }
                     elseif ($total -ge 60) { 'C' }
                     elseif ($total -ge 50) { 'D' }
                     else { 'F' }

            $gradeColor = if ($total -ge 80) { 'Green' }
                          elseif ($total -ge 60) { 'Yellow' }
                          else { 'Red' }

            return @{
                PackageId = $Id
                Score = $total
                Grade = $grade
                GradeColor = $gradeColor
                Breakdown = $score
                Details = $details
            }
        }
    }

    process {
        $ids = @()
        if ($AllInstalled) {
            # Only winget-sourced packages have winget-pkgs manifests
            $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue | Where-Object { $_.Source -eq 'winget' }
            $ids = @($installed | ForEach-Object { $_.Id })
            if (-not (Get-WingetBatchGitHubToken) -and $ids.Count -gt 15) {
                Write-Warning "Scoring $($ids.Count) packages needs about $($ids.Count * 3) GitHub API requests; without a token the limit is 60/hour. Run New-WingetBatchGitHubToken first."
            }
            Write-Host "`n  Scoring $($ids.Count) installed packages...`n" -ForegroundColor Cyan
        } else {
            $ids = $PackageId
        }

        $i = 0
        foreach ($id in $ids) {
            $i++
            if ($AllInstalled) {
                Write-Progress -Activity "Health Scoring" -Status "[$i/$($ids.Count)] $id" -PercentComplete (($i / $ids.Count) * 100)
            }

            $health = Get-SingleHealthScore -Id $id

            # Filter by min score
            if ($health.Score -lt $MinScore -or -not $AllInstalled) {
                $results.Add([PSCustomObject]@{
                    PackageId = $health.PackageId
                    Score = $health.Score
                    Grade = $health.Grade
                    Freshness = $health.Breakdown.Freshness
                    PublisherActivity = $health.Breakdown.PublisherActivity
                    VersionMaturity = $health.Breakdown.VersionMaturity
                    ManifestQuality = $health.Breakdown.ManifestQuality
                    UpdateCadence = $health.Breakdown.UpdateCadence
                    Details = $health.Details
                })

                # Display
                $bar = ('█' * [Math]::Round($health.Score / 5)).PadRight(20, '░')
                Write-Host "  $($health.Grade) " -NoNewline -ForegroundColor $health.GradeColor
                Write-Host "$bar " -NoNewline -ForegroundColor $health.GradeColor
                Write-Host "$($health.Score)/100 " -NoNewline -ForegroundColor White
                Write-Host $id -ForegroundColor Cyan

                if ($Detailed) {
                    Write-Host "      Freshness:        $($health.Breakdown.Freshness)/25" -ForegroundColor DarkGray
                    Write-Host "      Publisher:        $($health.Breakdown.PublisherActivity)/20" -ForegroundColor DarkGray
                    Write-Host "      Version Maturity: $($health.Breakdown.VersionMaturity)/20" -ForegroundColor DarkGray
                    Write-Host "      Manifest Quality: $($health.Breakdown.ManifestQuality)/20" -ForegroundColor DarkGray
                    Write-Host "      Update Cadence:   $($health.Breakdown.UpdateCadence)/15" -ForegroundColor DarkGray
                    Write-Host "      Source: $($health.Details.SourceTrust)" -ForegroundColor DarkGray
                    if ($health.Details.LastModified) {
                        Write-Host "      Last updated: $($health.Details.LastModified.ToString('yyyy-MM-dd')) (v$($health.Details.LatestVersion))" -ForegroundColor DarkGray
                    }
                    if ($health.Details.PublisherRepo) {
                        Write-Host "      URL: $($health.Details.PublisherRepo)" -ForegroundColor DarkGray
                    }
                    Write-Host ""
                }
            }
        }

        if ($AllInstalled) { Write-Progress -Activity "Health Scoring" -Completed }
    }

    end {
        # Summary
        if ($results.Count -gt 1) {
            $avg = [Math]::Round(($results | Measure-Object Score -Average).Average, 1)
            $lowCount = ($results | Where-Object { $_.Score -lt 50 }).Count
            Write-Host ""
            Write-Host "  Summary: $($results.Count) packages scored | Average: $avg/100 | Below 50: $lowCount" -ForegroundColor DarkGray
            Write-Host ""
        }

        # Export
        if ($ExportReport) {
            $report = @{
                Timestamp = (Get-Date).ToString('o')
                Hostname = $env:COMPUTERNAME
                PackageCount = $results.Count
                AverageScore = [Math]::Round(($results | Measure-Object Score -Average).Average, 1)
                Packages = @($results | ForEach-Object {
                    @{ Id = $_.PackageId; Score = $_.Score; Grade = $_.Grade }
                })
            }
            $report | ConvertTo-Json -Depth 5 | Set-Content -Path $ExportReport -Encoding UTF8
            Write-Host "  Report saved: $ExportReport" -ForegroundColor Green
        }

        return $results
    }
}
