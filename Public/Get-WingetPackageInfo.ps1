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

        # Also check if installed locally (exact ID match; -Id alone is a substring search)
        $localPkg = Microsoft.WinGet.Client\Get-WinGetPackage -Id $package.Id -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1

        # Extended details come from the package's winget-pkgs manifest
        $manifest = $null
        $versionList = $null
        if ($ShowManifest -or $ShowVersions) {
            Write-Host ""
            Write-Host "  Fetching extended details from winget-pkgs..." -ForegroundColor DarkGray
            try {
                $versionList = @(Get-WingetPkgsVersions -PackageId $package.Id)
                if ($versionList.Count -gt 0) {
                    $manifest = Get-WingetPkgsManifest -PackageId $package.Id -Version $versionList[0].Name
                }
            }
            catch {
                $status = [int]$_.Exception.Response.StatusCode
                if ($status -in 403, 429) {
                    Write-Host "  GitHub rate limit reached - run New-WingetBatchGitHubToken for 5,000 requests/hour." -ForegroundColor Yellow
                }
                else {
                    Write-Host "  Package not found in winget-pkgs (it may come from another source)." -ForegroundColor DarkGray
                }
            }
        }

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
            if ($localPkg.IsUpdateAvailable -and @($localPkg.AvailableVersions).Count -gt 0) {
                $infoItems['Latest Version'] = @($localPkg.AvailableVersions)[0]
            }
        }

        if ($manifest) {
            $fields = [ordered]@{
                'Publisher'   = 'Publisher'
                'Description' = 'ShortDescription'
                'License'     = 'License'
                'License URL' = 'LicenseUrl'
                'Homepage'    = 'PackageUrl'
                'Release Notes' = 'ReleaseNotesUrl'
                'Moniker'     = 'Moniker'
            }
            foreach ($label in $fields.Keys) {
                $value = Get-WingetYamlValue -Yaml $manifest.Locale -Key $fields[$label]
                if ($value) { $infoItems[$label] = $value }
            }
            $installerType = Get-WingetYamlValue -Yaml $manifest.Installer -Key 'InstallerType'
            if (-not $installerType -and $manifest.Installer -match '(?m)^\s+InstallerType:\s*(\S+)') { $installerType = $Matches[1] }
            if ($installerType) { $infoItems['Installer'] = $installerType }
        }

        # Calculate max key width for alignment
        $maxKeyLen = ($infoItems.Keys | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum

        foreach ($key in $infoItems.Keys) {
            $paddedKey = $key.PadRight($maxKeyLen + 2)
            $value = $infoItems[$key]
            $color = switch ($key) {
                'Update Available' { if ($value -eq 'Yes') { 'Yellow' } else { 'Green' } }
                'Id' { 'Cyan' }
                { $_ -in 'License URL', 'Homepage', 'Release Notes' } { 'Cyan' }
                default { 'White' }
            }
            Write-Host "  $paddedKey" -ForegroundColor Gray -NoNewline
            Write-Host $value -ForegroundColor $color
        }

        if ($ShowVersions -and $versionList) {
            Write-Host ""
            Write-Host "  Available Versions ($($versionList.Count)):" -ForegroundColor White
            $showCount = [Math]::Min($versionList.Count, 15)
            for ($i = 0; $i -lt $showCount; $i++) {
                $v = $versionList[$i].Name
                $isInstalled = $localPkg -and (Compare-WingetVersion -ReferenceVersion $localPkg.InstalledVersion -DifferenceVersion $v) -eq 0
                $marker = if ($isInstalled) { ' * installed' } else { '' }
                Write-Host "    - $v$marker" -ForegroundColor $(if ($isInstalled) { 'Green' } else { 'Gray' })
            }
            if ($versionList.Count -gt 15) {
                Write-Host "    ... and $($versionList.Count - 15) more" -ForegroundColor DarkGray
            }
        }

        if ($ShowManifest -and $manifest -and $manifest.Installer) {
            Write-Host ""
            Write-Host "  Installer Manifest (v$($manifest.Version)):" -ForegroundColor White
            Write-Host "  $('─' * 50)" -ForegroundColor DarkGray
            $manifestLines = $manifest.Installer -split "\r?\n"
            foreach ($line in ($manifestLines | Select-Object -First 40)) {
                Write-Host "  $line" -ForegroundColor DarkGray
            }
            if ($manifestLines.Count -gt 40) {
                Write-Host "  ... (truncated)" -ForegroundColor DarkGray
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
