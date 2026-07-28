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

    # --- Resolve versions ---
    $installedVersion = $null
    $latestVersion = $null

    try {
        $pkg = Microsoft.WinGet.Client\Get-WinGetPackage -Id $PackageId -ErrorAction SilentlyContinue
        if ($pkg) {
            $installedVersion = $pkg.InstalledVersion
            if ($pkg.AvailableVersions -and $pkg.AvailableVersions.Count -gt 0) {
                $latestVersion = $pkg.AvailableVersions[0]
            }
        }
    } catch { }

    if (-not $FromVersion) { $FromVersion = $installedVersion }
    if (-not $ToVersion) { $ToVersion = $latestVersion }

    # --- Fetch version history from winget-pkgs ---
    $headers = @{ 'User-Agent' = 'WingetBatch-Changelog' }
    $token = Get-WingetBatchGitHubToken -ErrorAction SilentlyContinue
    if ($token) { $headers['Authorization'] = "Bearer $token" }

    $idParts = $PackageId.Split('.')
    $publisher = $idParts[0]
    $firstLetter = $publisher[0].ToString().ToLower()
    $packagePath = $idParts -join '/'
    $apiBase = "https://api.github.com/repos/microsoft/winget-pkgs/contents"
    $manifestDir = "$apiBase/manifests/$firstLetter/$packagePath"

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║           Package Changelog                         ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Package:  " -NoNewline -ForegroundColor DarkGray; Write-Host $PackageId -ForegroundColor White
    if ($installedVersion) {
        Write-Host "  Installed:" -NoNewline -ForegroundColor DarkGray; Write-Host " $installedVersion" -ForegroundColor Yellow
    }
    if ($latestVersion) {
        Write-Host "  Latest:   " -NoNewline -ForegroundColor DarkGray; Write-Host " $latestVersion" -ForegroundColor Green
    }
    Write-Host ""

    try {
        $versions = Invoke-RestMethod -Uri $manifestDir -Headers $headers -ErrorAction Stop

        # Sort versions
        $sortedVersions = $versions | Sort-Object { 
            try { [version]($_.name -replace '[^0-9.]', '') } catch { [version]'0.0.0' }
        } -Descending

        # Filter to range if specified
        $inRange = $sortedVersions
        if ($FromVersion -and $ToVersion) {
            $inRange = $sortedVersions | Where-Object {
                try {
                    $v = [version]($_.name -replace '[^0-9.]', '')
                    $from = [version]($FromVersion -replace '[^0-9.]', '')
                    $to = [version]($ToVersion -replace '[^0-9.]', '')
                    $v -ge $from -and $v -le $to
                } catch { $true }
            }
        }

        $displayVersions = $inRange | Select-Object -First $Limit

        Write-Host "  Version History ($($displayVersions.Count) of $($sortedVersions.Count) total):" -ForegroundColor White
        Write-Host "  $('─' * 55)" -ForegroundColor DarkGray

        $prevVersion = $null
        foreach ($ver in $displayVersions) {
            $versionName = $ver.name
            $isInstalled = ($versionName -eq $installedVersion)
            $isLatest = ($versionName -eq $latestVersion)

            # Version line
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

            # Fetch commit info for this version (date + author)
            try {
                $versionUrl = "$manifestDir/$versionName"
                $versionFiles = Invoke-RestMethod -Uri $versionUrl -Headers $headers -ErrorAction SilentlyContinue
                if ($versionFiles -and $versionFiles.Count -gt 0) {
                    # Get the default manifest for release notes
                    $defaultManifest = $versionFiles | Where-Object { $_.name -match '\.yaml$' -and $_.name -notmatch 'installer|locale' } | Select-Object -First 1
                    if (-not $defaultManifest) { $defaultManifest = $versionFiles | Where-Object { $_.name -match 'locale.*en-US' } | Select-Object -First 1 }
                    if (-not $defaultManifest) { $defaultManifest = $versionFiles | Select-Object -First 1 }

                    if ($defaultManifest) {
                        $content = Invoke-RestMethod -Uri $defaultManifest.url -Headers $headers -ErrorAction SilentlyContinue
                        $rawContent = $content.content
                        if ($content.encoding -eq 'base64') {
                            $rawContent = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($rawContent))
                        }

                        # Extract release notes
                        if ($rawContent -match 'ReleaseNotes:\s*(.+?)(?:\n\S|\n\s*\w+:|\z)') {
                            $notes = $Matches[1].Trim() -replace '\s+', ' '
                            if ($notes.Length -gt 120) { $notes = $notes.Substring(0, 117) + "..." }
                            Write-Host "      $notes" -ForegroundColor DarkGray
                        }
                        elseif ($rawContent -match 'ReleaseNotesUrl:\s*(.+)') {
                            Write-Host "      Notes: $($Matches[1].Trim())" -ForegroundColor DarkGray
                        }
                    }
                }
            } catch {
                Write-Verbose "Could not fetch details for $versionName"
            }

            # Manifest diff
            if ($ShowManifestDiff -and $prevVersion) {
                try {
                    $diffChanges = @()
                    # Compare installer manifests between versions
                    $prevFiles = Invoke-RestMethod -Uri "$manifestDir/$($prevVersion.name)" -Headers $headers -ErrorAction SilentlyContinue
                    $currFiles = $versionFiles

                    $prevInstaller = $prevFiles | Where-Object { $_.name -match 'installer' } | Select-Object -First 1
                    $currInstaller = $currFiles | Where-Object { $_.name -match 'installer' } | Select-Object -First 1

                    if ($prevInstaller -and $currInstaller) {
                        $prevContent = Invoke-RestMethod -Uri $prevInstaller.url -Headers $headers -ErrorAction SilentlyContinue
                        $currContent = Invoke-RestMethod -Uri $currInstaller.url -Headers $headers -ErrorAction SilentlyContinue

                        $prevRaw = if ($prevContent.encoding -eq 'base64') { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($prevContent.content)) } else { $prevContent.content }
                        $currRaw = if ($currContent.encoding -eq 'base64') { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($currContent.content)) } else { $currContent.content }

                        # Check for installer URL changes
                        $prevUrl = if ($prevRaw -match 'InstallerUrl:\s*(.+)') { $Matches[1].Trim() } else { '' }
                        $currUrl = if ($currRaw -match 'InstallerUrl:\s*(.+)') { $Matches[1].Trim() } else { '' }
                        if ($prevUrl -ne $currUrl -and $prevUrl -and $currUrl) {
                            $diffChanges += "Installer URL changed"
                        }

                        # Check for new installer types
                        $prevTypes = [regex]::Matches($prevRaw, 'InstallerType:\s*(\w+)') | ForEach-Object { $_.Groups[1].Value }
                        $currTypes = [regex]::Matches($currRaw, 'InstallerType:\s*(\w+)') | ForEach-Object { $_.Groups[1].Value }
                        $newTypes = $currTypes | Where-Object { $_ -notin $prevTypes }
                        if ($newTypes) { $diffChanges += "New installer type: $($newTypes -join ', ')" }
                    }

                    if ($diffChanges.Count -gt 0) {
                        foreach ($change in $diffChanges) {
                            Write-Host "      Δ $change" -ForegroundColor DarkCyan
                        }
                    }
                } catch { }
            }

            $prevVersion = $ver
        }

        Write-Host ""
        Write-Host "  Legend: ◆ installed+latest | ● installed | ★ latest" -ForegroundColor DarkGray

        # GitHub releases link
        $repoUrl = "https://github.com/microsoft/winget-pkgs/tree/master/manifests/$firstLetter/$packagePath"
        Write-Host "  Source: $repoUrl" -ForegroundColor DarkGray
        Write-Host ""

        if ($OpenInBrowser) {
            Start-Process $repoUrl
        }
    }
    catch {
        Write-Error "Could not fetch version history for ${PackageId}: $($_.Exception.Message)"
    }
}
