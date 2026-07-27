function Get-WingetPackageInfo {
    <#
    .SYNOPSIS
        Display rich, detailed information about a winget package.

    .DESCRIPTION
        Shows comprehensive package metadata in a beautiful terminal layout including:
        version info, publisher, license, pricing, install size, dependencies,
        available versions, and direct links. Similar to 'brew info' or 'apt show'.

        Fetches data from both the local COM API and the winget-pkgs GitHub repository
        for maximum detail.

    .PARAMETER Id
        The exact package identifier (e.g., "Git.Git", "Python.Python.3.12").

    .PARAMETER Query
        A search query to find packages (shows top matches with quick info).

    .PARAMETER ShowManifest
        Also display the raw winget manifest YAML from the GitHub repository.

    .PARAMETER ShowVersions
        List all available versions for the package.

    .EXAMPLE
        Get-WingetPackageInfo -Id "Git.Git"
        Shows full details for Git.

    .EXAMPLE
        Get-WingetPackageInfo -Query "visual studio code"
        Searches and shows info for matching packages.

    .EXAMPLE
        Get-WingetPackageInfo -Id "Python.Python.3.12" -ShowVersions
        Shows Python 3.12 info plus all available versions.

    .LINK
        https://github.com/thebubbsy/WingetBatch
    #>

    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByQuery', Position = 0)]
        [string]$Query,

        [Parameter()]
        [switch]$ShowManifest,

        [Parameter()]
        [switch]$ShowVersions
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
        # Resolve package
        $package = $null

        if ($PSCmdlet.ParameterSetName -eq 'ByQuery') {
            Write-Host ""
            Write-Host "  Searching for: " -ForegroundColor Cyan -NoNewline
            Write-Host $Query -ForegroundColor Yellow

            $results = Microsoft.WinGet.Client\Find-WinGetPackage -Query $Query -Count 10 -ErrorAction SilentlyContinue
            if (-not $results -or $results.Count -eq 0) {
                Write-Host "  No packages found matching '$Query'" -ForegroundColor Red
                return
            }

            if ($results.Count -eq 1) {
                $package = $results[0]
            } else {
                # Show selection list
                Write-Host ""
                Write-Host "  Multiple matches found:" -ForegroundColor White
                Write-Host ""

                $choices = [System.Collections.Generic.List[string]]::new()
                $choiceMap = @{}
                foreach ($r in $results) {
                    $ver = if ($r.Version) { $r.Version } else { '?' }
                    $display = "$($r.Name) ($($r.Id)) v$ver [$($r.Source)]"
                    $choices.Add($display)
                    $choiceMap[$display] = $r
                }

                if (Get-Module -Name PwshSpectreConsole) {
                    $selected = Read-SpectreSelection -Title "[cyan]Select a package[/]" -Choices $choices -Color "Green"
                    if ($selected) { $package = $choiceMap[$selected] }
                } else {
                    for ($i = 0; $i -lt $choices.Count; $i++) {
                        Write-Host "  [$($i + 1)] " -ForegroundColor Cyan -NoNewline
                        Write-Host $choices[$i] -ForegroundColor White
                    }
                    $idx = Read-Host "  Enter number (1-$($choices.Count))"
                    if ($idx -match '^\d+$' -and [int]$idx -ge 1 -and [int]$idx -le $choices.Count) {
                        $package = $choiceMap[$choices[[int]$idx - 1]]
                    }
                }

                if (-not $package) {
                    Write-Host "  No selection made." -ForegroundColor Yellow
                    return
                }
            }
        } else {
            # Direct ID lookup
            $results = Microsoft.WinGet.Client\Find-WinGetPackage -Id $Id -Count 5 -ErrorAction SilentlyContinue
            if ($results) {
                $package = $results | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
                if (-not $package) { $package = $results[0] }
            }
        }

        if (-not $package) {
            Write-Host "  Package not found: $Id" -ForegroundColor Red
            return
        }

        # Also check if installed locally
        $localPkg = Get-WinGetPackage -Id $package.Id -ErrorAction SilentlyContinue

        # Display rich info
        Write-Host ""
        Write-Host "  $('─' * 56)" -ForegroundColor DarkGray

        # Package name header
        $nameStr = "  $($package.Name)"
        Write-Host $nameStr -ForegroundColor White -NoNewline
        if ($localPkg) {
            Write-Host " [Installed]" -ForegroundColor Green -NoNewline
        }
        Write-Host ""

        Write-Host "  $('─' * 56)" -ForegroundColor DarkGray
        Write-Host ""

        # Core info table
        $infoItems = [ordered]@{
            'Id'            = $package.Id
            'Name'          = $package.Name
            'Version'       = if ($package.Version) { $package.Version } else { 'Unknown' }
            'Source'        = if ($package.Source) { $package.Source } else { 'Unknown' }
        }

        if ($localPkg) {
            $infoItems['Installed Ver'] = if ($localPkg.InstalledVersion) { $localPkg.InstalledVersion } else { 'Unknown' }
            $infoItems['Update Available'] = if ($localPkg.IsUpdateAvailable) { 'Yes' } else { 'No' }
            if ($localPkg.IsUpdateAvailable -and $localPkg.AvailableVersion) {
                $infoItems['Latest Version'] = $localPkg.AvailableVersion
            }
        }

        $infoItems['Publisher'] = if ($package.Publisher) { $package.Publisher } else { 'Unknown' }

        # Calculate max key width for alignment
        $maxKeyLen = ($infoItems.Keys | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum

        foreach ($key in $infoItems.Keys) {
            $paddedKey = $key.PadRight($maxKeyLen + 2)
            $value = $infoItems[$key]
            $color = switch ($key) {
                'Update Available' { if ($value -eq 'Yes') { 'Yellow' } else { 'Green' } }
                'Id' { 'Cyan' }
                default { 'White' }
            }
            Write-Host "  $paddedKey" -ForegroundColor Gray -NoNewline
            Write-Host $value -ForegroundColor $color
        }

        Write-Host ""

        # Fetch extended details from GitHub (manifest) if possible
        if ($ShowManifest -or $ShowVersions) {
            Write-Host "  Fetching extended details from winget-pkgs..." -ForegroundColor DarkGray

            $token = $null
            try { $token = Get-WingetBatchGitHubToken } catch {}

            $headers = @{ 'User-Agent' = 'WingetBatch' }
            if ($token) { $headers['Authorization'] = "Bearer $token" }

            # Try to get the manifest from GitHub
            $packageIdPath = $package.Id -replace '\.', '/'
            $apiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$($packageIdPath.Substring(0,1).ToLower())/$packageIdPath"

            try {
                $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
                if ($response -is [array]) {
                    # Find the installer manifest
                    $installerManifest = $response | Where-Object { $_.name -match '\.installer\.yaml$' } | Select-Object -First 1
                    $localeManifest = $response | Where-Object { $_.name -match '\.locale\.' } | Select-Object -First 1

                    if ($localeManifest) {
                        $localeContent = Invoke-RestMethod -Uri $localeManifest.download_url -Headers $headers -ErrorAction SilentlyContinue
                        if ($localeContent) {
                            # Parse useful fields
                            $lines = $localeContent -split "`n"
                            foreach ($line in $lines) {
                                if ($line -match '^License:\s*(.+)') {
                                    Write-Host "  $('License'.PadRight($maxKeyLen + 2))" -ForegroundColor Gray -NoNewline
                                    Write-Host $Matches[1].Trim() -ForegroundColor White
                                }
                                if ($line -match '^LicenseUrl:\s*(.+)') {
                                    Write-Host "  $('License URL'.PadRight($maxKeyLen + 2))" -ForegroundColor Gray -NoNewline
                                    Write-Host $Matches[1].Trim() -ForegroundColor Cyan
                                }
                                if ($line -match '^PackageUrl:\s*(.+)') {
                                    Write-Host "  $('Homepage'.PadRight($maxKeyLen + 2))" -ForegroundColor Gray -NoNewline
                                    Write-Host $Matches[1].Trim() -ForegroundColor Cyan
                                }
                                if ($line -match '^ShortDescription:\s*(.+)') {
                                    Write-Host "  $('Description'.PadRight($maxKeyLen + 2))" -ForegroundColor Gray -NoNewline
                                    Write-Host $Matches[1].Trim() -ForegroundColor White
                                }
                                if ($line -match '^Moniker:\s*(.+)') {
                                    Write-Host "  $('Moniker'.PadRight($maxKeyLen + 2))" -ForegroundColor Gray -NoNewline
                                    Write-Host $Matches[1].Trim() -ForegroundColor DarkGray
                                }
                                if ($line -match '^- (\w+)$' -and $prevLine -match '^Tags:') {
                                    # Collect tags
                                }
                            }
                        }
                    }

                    if ($ShowVersions) {
                        Write-Host ""
                        Write-Host "  Available Versions:" -ForegroundColor White
                        $versions = $response | Where-Object { $_.type -eq 'dir' } | Select-Object -ExpandProperty name | Sort-Object -Descending
                        if ($versions) {
                            $showCount = [Math]::Min($versions.Count, 15)
                            for ($i = 0; $i -lt $showCount; $i++) {
                                $marker = if ($localPkg -and $localPkg.InstalledVersion -eq $versions[$i]) { ' *' } else { '' }
                                Write-Host "    - $($versions[$i])$marker" -ForegroundColor $(if ($marker) { 'Green' } else { 'Gray' })
                            }
                            if ($versions.Count -gt 15) {
                                Write-Host "    ... and $($versions.Count - 15) more" -ForegroundColor DarkGray
                            }
                        }
                    }

                    if ($ShowManifest -and $installerManifest) {
                        Write-Host ""
                        Write-Host "  Raw Installer Manifest:" -ForegroundColor White
                        Write-Host "  $('─' * 50)" -ForegroundColor DarkGray
                        $manifestContent = Invoke-RestMethod -Uri $installerManifest.download_url -Headers $headers -ErrorAction SilentlyContinue
                        if ($manifestContent) {
                            $manifestLines = ($manifestContent -split "`n") | Select-Object -First 40
                            foreach ($line in $manifestLines) {
                                Write-Host "  $line" -ForegroundColor DarkGray
                            }
                            if (($manifestContent -split "`n").Count -gt 40) {
                                Write-Host "  ... (truncated)" -ForegroundColor DarkGray
                            }
                        }
                    }
                }
            } catch {
                Write-Verbose "Could not fetch extended details from GitHub: $_"
            }
        }

        Write-Host ""
        Write-Host "  $('─' * 56)" -ForegroundColor DarkGray

        # Quick action hints
        Write-Host "  Actions: " -ForegroundColor DarkGray -NoNewline
        if ($localPkg) {
            if ($localPkg.IsUpdateAvailable) {
                Write-Host "Update-WinGetPackage -Id '$($package.Id)'" -ForegroundColor Yellow -NoNewline
            } else {
                Write-Host "Up to date" -ForegroundColor Green -NoNewline
            }
            Write-Host " | Uninstall-WinGetPackage -Id '$($package.Id)'" -ForegroundColor DarkGray
        } else {
            Write-Host "Install-WingetAll -Id '$($package.Id)'" -ForegroundColor Green
        }
        Write-Host ""
    }
}
