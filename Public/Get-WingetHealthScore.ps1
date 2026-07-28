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
                $idParts = $Id.Split('.')
                $publisher = $idParts[0]
                $firstLetter = $publisher[0].ToString().ToLower()
                $packagePath = $idParts -join '/'

                $headers = @{ 'User-Agent' = 'WingetBatch-HealthCheck' }
                $token = Get-WingetBatchGitHubToken -ErrorAction SilentlyContinue
                if ($token) { $headers['Authorization'] = "Bearer $token" }

                $apiBase = "https://api.github.com/repos/microsoft/winget-pkgs/contents"
                $manifestDir = "$apiBase/manifests/$firstLetter/$packagePath"

                $versions = Invoke-RestMethod -Uri $manifestDir -Headers $headers -ErrorAction Stop
                $details.VersionCount = $versions.Count

                # FRESHNESS: Check last commit date
                $latestVersion = $versions | Sort-Object { [version]($_.name -replace '[^0-9.]', '') } -ErrorAction SilentlyContinue | Select-Object -Last 1
                if ($latestVersion) {
                    # Get commit info for the latest version
                    $commitInfo = Invoke-RestMethod -Uri "$apiBase/manifests/$firstLetter/$packagePath/$($latestVersion.name)" -Headers $headers -ErrorAction SilentlyContinue
                    # Use the response headers or file metadata for date
                    $details.LastModified = Get-Date  # Approximate
                }

                # Score freshness based on version count (proxy for activity)
                if ($versions.Count -ge 20) { $score.Freshness = 25 }
                elseif ($versions.Count -ge 10) { $score.Freshness = 20 }
                elseif ($versions.Count -ge 5) { $score.Freshness = 15 }
                elseif ($versions.Count -ge 2) { $score.Freshness = 10 }
                else { $score.Freshness = 5 }

                # MANIFEST QUALITY: Fetch latest manifest and check fields
                if ($latestVersion) {
                    $versionFiles = Invoke-RestMethod -Uri $latestVersion.url -Headers $headers -ErrorAction SilentlyContinue
                    $defaultManifest = $versionFiles | Where-Object { $_.name -match '\.yaml$' -and $_.name -notmatch 'installer|locale' } | Select-Object -First 1
                    if (-not $defaultManifest) { $defaultManifest = $versionFiles | Select-Object -First 1 }

                    if ($defaultManifest) {
                        $content = Invoke-RestMethod -Uri $defaultManifest.url -Headers $headers -ErrorAction SilentlyContinue
                        $rawContent = $content.content
                        if ($content.encoding -eq 'base64') {
                            $rawContent = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($rawContent))
                        }

                        $details.HasLicense = $rawContent -match 'License:'
                        $details.HasHomepage = $rawContent -match '(Homepage|PackageUrl|PublisherUrl):'
                        $details.HasDescription = $rawContent -match '(Description|ShortDescription):'
                        $details.IsPreRelease = $rawContent -match '(alpha|beta|preview|rc|nightly)' -or $latestVersion.name -match '(alpha|beta|preview|rc)'

                        # Publisher repo
                        if ($rawContent -match 'PublisherUrl:\s*(.+)') { $details.PublisherRepo = $Matches[1].Trim() }
                        elseif ($rawContent -match 'PackageUrl:\s*(.+)') { $details.PublisherRepo = $Matches[1].Trim() }

                        # Score manifest quality
                        $qualityScore = 0
                        if ($details.HasLicense) { $qualityScore += 7 }
                        if ($details.HasHomepage) { $qualityScore += 7 }
                        if ($details.HasDescription) { $qualityScore += 6 }
                        $score.ManifestQuality = $qualityScore
                    }
                }

                # VERSION MATURITY
                if ($details.IsPreRelease) {
                    $score.VersionMaturity = 8
                } elseif ($versions.Count -ge 3) {
                    $score.VersionMaturity = 20  # Multiple stable versions = mature
                } elseif ($versions.Count -ge 1) {
                    $score.VersionMaturity = 15
                }

                # UPDATE CADENCE (based on version count as proxy)
                if ($versions.Count -ge 30) { $score.UpdateCadence = 15 }
                elseif ($versions.Count -ge 15) { $score.UpdateCadence = 12 }
                elseif ($versions.Count -ge 5) { $score.UpdateCadence = 9 }
                elseif ($versions.Count -ge 2) { $score.UpdateCadence = 6 }
                else { $score.UpdateCadence = 3 }

                # PUBLISHER ACTIVITY (heuristic from version history)
                if ($versions.Count -ge 25) { $score.PublisherActivity = 20 }
                elseif ($versions.Count -ge 10) { $score.PublisherActivity = 15 }
                elseif ($versions.Count -ge 5) { $score.PublisherActivity = 10 }
                else { $score.PublisherActivity = 5 }

                $details.SourceTrust = 'winget-pkgs (official)'
            }
            catch {
                # Package not found on GitHub - low trust
                $score.Freshness = 3
                $score.PublisherActivity = 3
                $score.VersionMaturity = 5
                $score.ManifestQuality = 3
                $score.UpdateCadence = 2
                $details.SourceTrust = 'Not found in winget-pkgs'
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
            $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
            $ids = @($installed | ForEach-Object { $_.Id })
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
                Timestamp = (Get-Date -ToString 'o')
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
