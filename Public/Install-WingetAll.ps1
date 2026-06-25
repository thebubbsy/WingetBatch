function Install-WingetAll {
    <#
    .SYNOPSIS
        Search for winget packages and install all results.

    .DESCRIPTION
        Searches for packages matching the provided search term and automatically
        installs all packages found in the search results.

    .PARAMETER SearchTerm
        The search term to find packages. Required.

    .PARAMETER Silent
        Skip the confirmation prompt and install immediately.

    .PARAMETER WhatIf
        Show what packages would be installed without actually installing them.

    .EXAMPLE
        Install-WingetAll "python"
        Searches for "python" and installs all matching packages after confirmation.

    .EXAMPLE
        Install-WingetAll "nodejs" -Silent
        Installs all nodejs packages without confirmation prompt.

    .EXAMPLE
        Install-WingetAll "python" -WhatIf
        Shows what would be installed without actually installing.

    .LINK
        https://github.com/microsoft/winget-cli
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [Alias('SearchTerm')]
        [string[]]$SearchTerms,

        [Parameter()]
        [switch]$Silent,

        [Parameter()]
        [switch]$WhatIf
    )

    begin {
        # Ensure Microsoft.WinGet.Client is available (COM API - no winget.exe PATH dependency)
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try {
                Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            }
            catch {
                Write-Error "Microsoft.WinGet.Client module is required. Install it with: Install-Module Microsoft.WinGet.Client -Force"
                return
            }
        }

        # Check if PwshSpectreConsole is available
        if (-not (Get-Module -ListAvailable -Name PwshSpectreConsole)) {
            Write-Warning "PwshSpectreConsole module not found. Installing..."
            try {
                Install-Module -Name PwshSpectreConsole -Scope CurrentUser -Force -SkipPublisherCheck
                Import-Module PwshSpectreConsole
            }
            catch {
                Write-Error "Failed to install PwshSpectreConsole. Interactive selection will not be available."
                Write-Error $_
            }
        }
        else {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }

        Write-Host "Searching for packages matching: " -ForegroundColor Cyan -NoNewline
        Write-Host ($SearchTerms -join ", ") -ForegroundColor Yellow
    }

    process {
        # Parse multiple search terms: handle both arrays (PowerShell comma list) and comma-separated strings
        $searchQueries = $SearchTerms | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' }
        $allPackages = [System.Collections.Generic.List[Object]]::new()

        foreach ($query in $searchQueries) {
            $query = $query.Trim()
            if ([string]::IsNullOrWhiteSpace($query)) { continue }

            Write-Host "Searching for: " -ForegroundColor Cyan -NoNewline
            Write-Host $query -ForegroundColor Yellow

            # Normalize query (collapse multiple spaces)
            $searchWords = $query -split '\s+' | Where-Object { $_ -ne '' }
            $normalizedQuery = $searchWords -join ' '

            # Combine all search results from each word
            # Use COM API for search — no winget.exe PATH dependency, no text parsing
            $queryPackages = [System.Collections.Generic.List[PSCustomObject]]::new()

            try {
                $comResults = Find-WinGetPackage -Query $query -ErrorAction Stop

                foreach ($result in $comResults) {
                    $packageId = $result.Id
                    $packageName = $result.Name
                    $packageVersion = if ($result.Version) { $result.Version } else { "Unknown" }
                    $packageSource = if ($result.Source) { $result.Source } else { "Unknown" }

                    # If multiple search words, filter to only packages matching ALL words (case-insensitive)
                    if ($searchWords.Count -gt 1) {
                        $matchesAll = $true
                        $combinedText = "$packageName $packageId"
                        foreach ($word in $searchWords) {
                            if ($combinedText.IndexOf($word, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                                $matchesAll = $false
                                break
                            }
                        }
                        if ($matchesAll) {
                            $queryPackages.Add([PSCustomObject]@{
                                Id = $packageId
                                Name = $packageName
                                Version = $packageVersion
                                Source = $packageSource
                                SearchTerm = $query
                            })
                        }
                    }
                    else {
                        $queryPackages.Add([PSCustomObject]@{
                            Id = $packageId
                            Name = $packageName
                            Version = $packageVersion
                            Source = $packageSource
                            SearchTerm = $query
                        })
                    }
                }
            }
            catch {
                Write-Warning "Failed to search for query: $query"
                Write-Warning "  $_"
            }

            if ($queryPackages.Count -eq 0) {
                Write-Warning "No packages found matching '$query'"
                continue
            }

            # Deduplicate packages within this query based on Id (preserving order)
            $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $uniqueQueryPackages = [System.Collections.Generic.List[PSCustomObject]]::new()

            foreach ($pkg in $queryPackages) {
                if ($seenIds.Add($pkg.Id)) {
                    $uniqueQueryPackages.Add($pkg)
                }
            }
            $allPackages.AddRange([array]$uniqueQueryPackages)
        }

        # Keep all packages (including potential duplicates across queries) for display
        $foundPackages = $allPackages

        # Build a lookup map for faster access to package details
        $pkgMap = @{}
        if ($null -ne $foundPackages) {
            foreach ($pkg in $foundPackages) {
                # Use the first encounter of a package ID to match original behavior of Select-Object -First 1
                # Check for null Id to prevent hashtable errors and cast to string for safety
                if ($null -ne $pkg.Id -and -not $pkgMap.ContainsKey([string]$pkg.Id)) {
                    $pkgMap[[string]$pkg.Id] = $pkg
                }
            }
        }

        if ($foundPackages.Count -eq 0) {
            Write-Warning "No packages found matching '$($SearchTerms -join ", ")'"
            return
        }

        Write-Host "`nFound " -ForegroundColor Green -NoNewline
        Write-Host "$($foundPackages.Count)" -ForegroundColor White -NoNewline
        Write-Host " package(s)" -ForegroundColor Green

        if ($WhatIf) {
            Write-Host "`n[WhatIf] Would display interactive selection for:" -ForegroundColor Yellow

            $groups = @{}
            foreach ($pkg in $foundPackages) {
                if (-not $groups.ContainsKey($pkg.SearchTerm)) {
                    $groups[$pkg.SearchTerm] = [System.Collections.Generic.List[PSCustomObject]]::new()
                }
                $groups[$pkg.SearchTerm].Add($pkg)
            }

            foreach ($term in $groups.Keys) {
                Write-Host "$($term):" -ForegroundColor Yellow
                foreach ($pkg in $groups[$term]) {
                    Write-Host "  • " -ForegroundColor Cyan -NoNewline
                    Write-Host "$($pkg.Name) ($($pkg.Id))" -ForegroundColor White -NoNewline
                    if ($pkg.Version -ne "Unknown") {
                        Write-Host " v$($pkg.Version)" -ForegroundColor Green -NoNewline
                    }
                    if ($pkg.Source) {
                        $sColor = if ($pkg.Source -match 'msstore') { "Magenta" } else { "Cyan" }
                        Write-Host " [$($pkg.Source)]" -ForegroundColor $sColor
                    } else { Write-Host "" }
                }
            }
            return
        }

        # Prepare choices for selection with SearchTerm grouping prefix
        # Consolidating loops to improve performance (avoid double iteration and regex operations)
        $packageChoices = [System.Collections.Generic.List[string]]::new()
        $packageMap = @{}

        foreach ($pkg in $foundPackages) {
            $sourceColor = if ($pkg.Source -match 'msstore') { "magenta" } else { "cyan" }
            $versionStr = if ($pkg.Version -ne "Unknown") { " [green]v$($pkg.Version)[/]" } else { "" }

            $term = ConvertTo-SpectreEscaped $pkg.SearchTerm
            $name = ConvertTo-SpectreEscaped $pkg.Name
            $id = ConvertTo-SpectreEscaped $pkg.Id
            $source = ConvertTo-SpectreEscaped $pkg.Source

            $displayString = "[yellow][[$term]][/] $name ($id)$versionStr [$sourceColor]$source[/]"

            $packageChoices.Add($displayString)
            $packageMap[$displayString] = $pkg.Id
        }

        $packagesToInstall = @()

        # Interactive selection using Spectre Console
        if (-not $Silent -and (Get-Module -Name PwshSpectreConsole)) {
            Write-Host ""

            try {
                # Create multi-selection prompt
                $selectedChoices = Read-SpectreMultiSelection -Title "[cyan]Select packages to install[/]" `
                    -Choices $packageChoices `
                    -PageSize 20 `
                    -Color "Green"

                if ($selectedChoices.Count -eq 0) {
                    Write-Host "`nNo packages selected. Exiting." -ForegroundColor Yellow
                    return
                }

                # Map back to IDs
                $packagesToInstall = $selectedChoices | ForEach-Object { $packageMap[$_] }

                Write-Host "`nSelected " -ForegroundColor Green -NoNewline
                Write-Host "$($packagesToInstall.Count)" -ForegroundColor White -NoNewline
                Write-Host " package(s) for installation" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to show interactive selection. Falling back to confirmation prompt."
                $packagesToInstall = $foundPackages.Id
            }
        }
        elseif (-not $Silent) {
            # Fallback for when Spectre Console is not available
            $packagesToInstall = $foundPackages.Id
        }
        else {
             # Silent mode
             $packagesToInstall = $foundPackages.Id
        }

        if (-not $Silent -and $packagesToInstall.Count -gt 0) {
            Write-Host "`nFetching package details..." -ForegroundColor DarkGray
            $configDir = Get-WingetBatchConfigDir

            $jobsResult = Start-PackageDetailJobs -PackageIds $packagesToInstall -ConfigDir $configDir
            $jobs = $jobsResult[0]

            if ($jobs.Count -gt 0) {
                Write-Host "Waiting for background jobs..." -ForegroundColor DarkGray
                $jobs | Wait-Job | Out-Null

                $allPackageDetails = @{}
                foreach ($job in $jobs) {
                    $jobResults = Receive-Job -Job $job
                    foreach ($key in $jobResults.Keys) {
                        $allPackageDetails[$key] = $jobResults[$key]
                        Set-PackageDetailsCache -PackageId $key -Details $jobResults[$key]
                    }
                    Remove-Job -Job $job -Force
                }

                # Fill missing
                foreach ($pkgId in $packagesToInstall) {
                    if (-not $allPackageDetails.ContainsKey($pkgId)) {
                        $allPackageDetails[$pkgId] = @{ Id = $pkgId }
                    }
                }

                Show-WingetPackageDetails -PackageIds $packagesToInstall -DetailsMap $allPackageDetails -FallbackInfo $foundPackages -FallbackMap $pkgMap

                # Ask for confirmation
                Write-Host "Press " -NoNewline -ForegroundColor Yellow
                Write-Host "Enter" -NoNewline -ForegroundColor White
                Write-Host " to install, or " -NoNewline -ForegroundColor Yellow
                Write-Host "Ctrl+C" -NoNewline -ForegroundColor Red
                Write-Host " to cancel..." -ForegroundColor Yellow
                try {
                    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                }
                catch {
                    # Ignore
                }
            }
        }

        Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
        Write-Host "Starting Installation Process" -ForegroundColor Cyan
        Write-Host ("=" * 60) -ForegroundColor Cyan

        $successCount = 0
        $failCount = 0

        # Deduplicate IDs to ensure we don't install the same package twice
        $uniquePackagesToInstall = $packagesToInstall | Select-Object -Unique

        if ($uniquePackagesToInstall.Count -gt 0) {
            # Build summary list first (raw data)
            $summaryList = [System.Collections.Generic.List[PSCustomObject]]::new()

            foreach ($packageId in $uniquePackagesToInstall) {
                $pkgInfo = $pkgMap[$packageId]

                # Try to get publisher from details if available
                $publisher = $null
                if ($null -ne $allPackageDetails -and $allPackageDetails.ContainsKey($packageId)) {
                    $details = $allPackageDetails[$packageId]
                    if ($details.PublisherName) { $publisher = $details.PublisherName }
                    elseif ($details.Publisher) { $publisher = $details.Publisher }
                }

                if (-not $publisher) { $publisher = "" }

                if ($pkgInfo) {
                    $summaryList.Add([PSCustomObject]@{
                        Name = $pkgInfo.Name
                        Id = $pkgInfo.Id
                        Version = $pkgInfo.Version
                        Source = $pkgInfo.Source
                        SearchTerm = $pkgInfo.SearchTerm
                        Publisher = $publisher
                    })
                } else {
                    $summaryList.Add([PSCustomObject]@{
                        Name = $packageId
                        Id = $packageId
                        Version = "Unknown"
                        Source = "Unknown"
                        SearchTerm = "Manual"
                        Publisher = $publisher
                    })
                }
            }

            # Use Spectre Console table if available for better formatting
            if (Get-Module -Name PwshSpectreConsole) {
                Write-Host ""
                Write-Host "Package Installation Summary ($($summaryList.Count) packages)" -ForegroundColor Cyan

                $spectreList = [System.Collections.Generic.List[PSCustomObject]]::new()

                # Check if we have multiple unique search terms in the summary
                $uniqueSearchTerms = $summaryList | Select-Object -ExpandProperty SearchTerm -Unique
                $showSearchTerm = ($uniqueSearchTerms | Measure-Object).Count -gt 1

                # Check if we have any publishers to show
                $showPublisher = ($summaryList | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Publisher) } | Measure-Object).Count -gt 0

                foreach ($item in $summaryList) {
                    $verColor = if ($item.Version -ne "Unknown") { "green" } else { "grey" }
                    $srcColor = if ($item.Source -match 'msstore') { "magenta" } else { "cyan" }

                    $obj = [ordered]@{
                        Name = "📦 " + (ConvertTo-SpectreEscaped $item.Name)
                        Id = ConvertTo-SpectreEscaped $item.Id
                        Version = "[$verColor]$($item.Version)[/]"
                        Source = "[$srcColor]$($item.Source)[/]"
                    }

                    if ($showPublisher) {
                        $obj['Publisher'] = if ($item.Publisher) { (ConvertTo-SpectreEscaped $item.Publisher) } else { "" }
                    }

                    if ($showSearchTerm) {
                        $obj['Search Term'] = "[grey]$(ConvertTo-SpectreEscaped $item.SearchTerm)[/]"
                    }

                    $spectreList.Add([PSCustomObject]$obj)
                }

                $spectreList | Format-SpectreTable | Out-Host
            }
            else {
                Write-Host "`nPackage Installation Summary ($($summaryList.Count) packages):" -ForegroundColor Cyan

                # Simple modification for fallback table too
                $showPublisher = ($summaryList | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Publisher) } | Measure-Object).Count -gt 0

                $fallbackList = $summaryList | Select-Object @{N='Name';E={"📦 " + $_.Name}}, Id, Version, Source, Publisher, SearchTerm

                $props = [System.Collections.Generic.List[string]]::new()
                $props.AddRange([string[]]@('Name', 'Id', 'Version', 'Source'))

                if ($showPublisher) {
                    $props.Add('Publisher')
                }

                if (($summaryList | Select-Object -ExpandProperty SearchTerm -Unique | Measure-Object).Count -gt 1) {
                    $props.Add('SearchTerm')
                }

                $fallbackList | Format-Table -Property $props -AutoSize | Out-Host
            }
        }

        foreach ($packageId in $uniquePackagesToInstall) {
            # Find info for better display (use lookup map)
            $pkgInfo = $pkgMap[$packageId]

            $pkgName = if ($pkgInfo) { $pkgInfo.Name } else { $packageId }
            $pkgVersion = if ($pkgInfo -and $pkgInfo.Version -ne "Unknown") { "v$($pkgInfo.Version)" } else { "" }
            $pkgSource = if ($pkgInfo -and $pkgInfo.Source -ne "Unknown") { $pkgInfo.Source } else { "" }

            Write-Host "`n>>> Installing: " -ForegroundColor Magenta -NoNewline
            Write-Host "$pkgName ($packageId)" -ForegroundColor White -NoNewline

            if ($pkgVersion) {
                Write-Host " $pkgVersion" -ForegroundColor Green -NoNewline
            }
            if ($pkgSource) {
                $sColor = if ($pkgSource -match 'msstore') { "Magenta" } else { "Cyan" }
                Write-Host " from $pkgSource" -ForegroundColor $sColor
            } else { Write-Host "" }

            try {
                Install-WinGetPackage -Id $packageId -Mode Silent -ErrorAction Stop | Out-Null
                Write-Host "[OK] Successfully installed " -ForegroundColor Green -NoNewline
                Write-Host $packageId -ForegroundColor White
                $successCount++
            }
            catch {
                Write-Host "[FAIL] Failed to install " -ForegroundColor Red -NoNewline
                Write-Host $packageId -ForegroundColor White -NoNewline
                Write-Host " ($_)" -ForegroundColor Red
                $failCount++
            }
        }

        Write-Host "`n" + ("=" * 60) -ForegroundColor Green
        Write-Host "Installation Complete" -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "Success: " -ForegroundColor Green -NoNewline
        Write-Host $successCount -ForegroundColor White -NoNewline
        Write-Host " | Failed: " -ForegroundColor Red -NoNewline
        Write-Host $failCount -ForegroundColor White
    }
}

