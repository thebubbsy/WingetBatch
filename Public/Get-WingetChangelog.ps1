function Get-WingetChangelog {
    <#
    .SYNOPSIS
        Show what changed between package versions (release notes diff).

    .DESCRIPTION
        Fetches release notes and changelog information between two versions
        of a package. Aggregates data from GitHub Releases, winget-pkgs commit
        history, and package manifest changes to answer: "What actually changed
        between v1.2 and v1.3?"

    .PARAMETER PackageId
        The package ID to check changelog for.

    .PARAMETER FromVersion
        Starting version (older). If omitted, uses installed version.

    .PARAMETER ToVersion
        Ending version (newer). If omitted, uses latest available.

    .PARAMETER ShowManifestDiff
        Also show changes to the winget manifest (installer URLs, switches, etc).

    .PARAMETER Limit
        Maximum number of versions to show in the changelog. Default: 10.

    .PARAMETER OpenInBrowser
        Open the GitHub releases page in the default browser.

    .EXAMPLE
        Get-WingetChangelog -PackageId "Microsoft.VisualStudioCode"
        Shows recent version changes for VS Code.

    .EXAMPLE
        Get-WingetChangelog -PackageId "Git.Git" -FromVersion "2.43.0" -ToVersion "2.45.0"
        Shows what changed between Git 2.43 and 2.45.

    .EXAMPLE
        Get-WingetChangelog -PackageId "Python.Python.3.12" -ShowManifestDiff
        Shows version history plus manifest changes.

    .NOTES
        Author: Matthew Bubb
        Data sourced from winget-pkgs GitHub repository commit history.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('Id')]
        [string]$PackageId,

        [string]$FromVersion,

        [string]$ToVersion,

        [switch]$ShowManifestDiff,

        [ValidateRange(1, 50)]
        [int]$Limit = 10,

        [switch]$OpenInBrowser
    )

    process {

        # --- Resolve versions ---
        $installedVersion = $null
        $latestVersion = $null

        try {
            $pkg = Microsoft.WinGet.Client\Get-WinGetPackage -Id $PackageId -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($pkg) {
                $installedVersion = $pkg.InstalledVersion
                if ($pkg.AvailableVersions -and $pkg.AvailableVersions.Count -gt 0) {
                    $latestVersion = $pkg.AvailableVersions[0]
                }
            }
        } catch { }

        # Default to "what changed since my version" only when there is something newer;
        # otherwise show the most recent $Limit versions
        if (-not $FromVersion -and $installedVersion -and $pkg.IsUpdateAvailable) { $FromVersion = $installedVersion }

        Write-Host ""
        Write-Host "  Package Changelog" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Package:  " -NoNewline -ForegroundColor DarkGray; Write-Host $PackageId -ForegroundColor White
        if ($installedVersion) {
            Write-Host "  Installed:" -NoNewline -ForegroundColor DarkGray; Write-Host " $installedVersion" -ForegroundColor Yellow
        }
        if ($latestVersion) {
            Write-Host "  Latest:   " -NoNewline -ForegroundColor DarkGray; Write-Host " $latestVersion" -ForegroundColor Green
        }
        Write-Host ""

        $packagePath = Get-WingetPkgsPackagePath -PackageId $PackageId
        $repoUrl = "https://github.com/microsoft/winget-pkgs/tree/master/$packagePath"

        try {
            $sortedVersions = @(Get-WingetPkgsVersions -PackageId $PackageId)
            if ($sortedVersions.Count -eq 0) { throw "No versions found in winget-pkgs." }
            if (-not $latestVersion) { $latestVersion = $sortedVersions[0].Name }

            # Keep versions inside the requested range (either bound may be omitted)
            $inRange = @($sortedVersions | Where-Object {
                (-not $FromVersion -or (Compare-WingetVersion -ReferenceVersion $_.Name -DifferenceVersion $FromVersion) -ge 0) -and
                (-not $ToVersion -or (Compare-WingetVersion -ReferenceVersion $_.Name -DifferenceVersion $ToVersion) -le 0)
            })
            if ($inRange.Count -eq 0) { $inRange = $sortedVersions }

            $displayVersions = @($inRange | Select-Object -First $Limit)

            if (-not (Get-WingetBatchGitHubToken) -and $displayVersions.Count -gt 10) {
                Write-Warning "Showing $($displayVersions.Count) versions uses about $($displayVersions.Count + 1) GitHub API requests (60/hour without a token)."
            }

            Write-Host "  Version History ($($displayVersions.Count) of $($sortedVersions.Count) total):" -ForegroundColor White
            Write-Host "  $('─' * 55)" -ForegroundColor DarkGray

            $prevManifest = $null
            # Oldest first when diffing so each entry shows what it changed
            foreach ($ver in $displayVersions) {
                $versionName = $ver.Name
                $isInstalled = $installedVersion -and (Compare-WingetVersion -ReferenceVersion $versionName -DifferenceVersion $installedVersion) -eq 0
                $isLatest = $latestVersion -and (Compare-WingetVersion -ReferenceVersion $versionName -DifferenceVersion $latestVersion) -eq 0

                $marker = if ($isInstalled -and $isLatest) { "◆ " }
                          elseif ($isInstalled) { "● " }
                          elseif ($isLatest) { "★ " }
                          else { "  " }

                $color = if ($isInstalled) { 'Yellow' } elseif ($isLatest) { 'Green' } else { 'White' }
                Write-Host "  $marker" -NoNewline -ForegroundColor $color
                Write-Host "v$versionName" -NoNewline -ForegroundColor $color
                if ($isInstalled) { Write-Host " (installed)" -NoNewline -ForegroundColor DarkYellow }
                if ($isLatest) { Write-Host " (latest)" -NoNewline -ForegroundColor DarkGreen }
                Write-Host ""

                $manifest = $null
                try {
                    $manifest = Get-WingetPkgsManifest -PackageId $PackageId -Version $versionName
                } catch {
                    $status = [int]$_.Exception.Response.StatusCode
                    if ($status -in 403, 429) {
                        Write-Warning "GitHub rate limit reached. Run New-WingetBatchGitHubToken for 5,000 requests/hour."
                        break
                    }
                    Write-Verbose "Could not fetch details for ${versionName}: $_"
                }

                if ($manifest) {
                    # Release notes live in the locale manifest
                    $notes = Get-WingetYamlValue -Yaml $manifest.Locale -Key 'ReleaseNotes'
                    $notesUrl = Get-WingetYamlValue -Yaml $manifest.Locale -Key 'ReleaseNotesUrl'
                    if ($notes) {
                        $notes = ($notes -replace '\s+', ' ').Trim()
                        if ($notes.Length -gt 160) { $notes = $notes.Substring(0, 157) + "..." }
                        Write-Host "      $notes" -ForegroundColor DarkGray
                    }
                    if ($notesUrl) {
                        Write-Host "      Notes: $notesUrl" -ForegroundColor DarkGray
                    }

                    # Manifest diff against the next-older displayed version
                    if ($ShowManifestDiff -and $prevManifest -and $manifest.Installer -and $prevManifest.Installer) {
                        $diffChanges = @()
                        $urlsNew = @([regex]::Matches($manifest.Installer, 'InstallerUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
                        $urlsOld = @([regex]::Matches($prevManifest.Installer, 'InstallerUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
                        $hostsNew = @($urlsNew | ForEach-Object { ([uri]$_).Host } | Select-Object -Unique)
                        $hostsOld = @($urlsOld | ForEach-Object { ([uri]$_).Host } | Select-Object -Unique)
                        if (Compare-Object $hostsNew $hostsOld) { $diffChanges += "Download host changed: $($hostsOld -join ', ') -> $($hostsNew -join ', ')" }

                        $typesNew = @([regex]::Matches($manifest.Installer, 'InstallerType:\s*(\w+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
                        $typesOld = @([regex]::Matches($prevManifest.Installer, 'InstallerType:\s*(\w+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
                        if (Compare-Object $typesNew $typesOld) { $diffChanges += "Installer type: $($typesOld -join ', ') -> $($typesNew -join ', ')" }

                        $archNew = @([regex]::Matches($manifest.Installer, 'Architecture:\s*(\w+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
                        $archOld = @([regex]::Matches($prevManifest.Installer, 'Architecture:\s*(\w+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
                        $added = @($archNew | Where-Object { $_ -notin $archOld })
                        $dropped = @($archOld | Where-Object { $_ -notin $archNew })
                        if ($added) { $diffChanges += "Architectures added: $($added -join ', ')" }
                        if ($dropped) { $diffChanges += "Architectures dropped: $($dropped -join ', ')" }

                        $depsNew = @([regex]::Matches($manifest.Installer, 'PackageIdentifier:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne $PackageId })
                        $depsOld = @([regex]::Matches($prevManifest.Installer, 'PackageIdentifier:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne $PackageId })
                        if (Compare-Object $depsNew $depsOld) { $diffChanges += "Dependencies: $(@($depsOld) -join ', ') -> $(@($depsNew) -join ', ')" }

                        foreach ($change in $diffChanges) {
                            # Changes are relative to the next-newer version shown above
                            Write-Host "      Δ (vs newer) $change" -ForegroundColor DarkCyan
                        }
                    }
                    $prevManifest = $manifest
                }
            }

            Write-Host ""
            Write-Host "  Legend: ◆ installed+latest | ● installed | ★ latest" -ForegroundColor DarkGray
            Write-Host "  Source: $repoUrl" -ForegroundColor DarkGray
            Write-Host ""

            if ($OpenInBrowser) {
                Start-Process $repoUrl
            }
        }
        catch {
            $status = [int]$_.Exception.Response.StatusCode
            if ($status -eq 404) {
                Write-Error "$PackageId was not found in winget-pkgs (it may come from another source)."
            }
            elseif ($status -in 403, 429) {
                Write-Error "GitHub rate limit reached. Run New-WingetBatchGitHubToken for 5,000 requests/hour."
            }
            else {
                Write-Error "Could not fetch version history for ${PackageId}: $($_.Exception.Message)"
            }
        }
    }
}
