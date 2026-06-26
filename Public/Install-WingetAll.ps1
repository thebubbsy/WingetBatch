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
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [Alias('SearchTerms')]
        [string[]]$Query,

        [Parameter()]
        [string[]]$Id,

        [Parameter()]
        [ValidateSet("Equals", "EqualsCaseInsensitive", "StartsWithCaseInsensitive", "ContainsCaseInsensitive")]
        [string]$MatchOption,

        [Parameter()]
        [string]$Source,

        [Parameter()]
        [int]$LimitResult = 100,

        [Parameter()]
        [switch]$Silent,

        [Parameter()]
        [ValidateSet("Default", "Silent", "Interactive")]
        [string]$Mode,

        [Parameter()]
        [ValidateSet("User", "Machine")]
        [string]$Scope,

        [Parameter()]
        [string]$Architecture,

        [Parameter()]
        [string]$Override,

        [Parameter()]
        [string]$Location,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$SkipDependencies,

        [Parameter()]
        [switch]$AllowHashMismatch,

        [Parameter()]
        [switch]$IWantToLiterallyInstallAllFuckingResults,

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

        # Check SQLite Index Health
        $wingetDir = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\Microsoft.Winget.Source_8wekyb3d8bbwe\winget"
        if (Test-Path "$wingetDir\source.db") {
            $dbAge = (Get-Date) - (Get-Item "$wingetDir\source.db").LastWriteTime
            if ($dbAge.TotalDays -gt 7) {
                Write-Host ""
                Write-Host " [!] Your Winget local index cache is outdated ($([Math]::Floor($dbAge.TotalDays)) days old) or fragmented." -ForegroundColor Yellow
                Write-Host "     This can severely degrade search performance and return stale results." -ForegroundColor Gray
                Write-Host "     Recommendation: Run '" -ForegroundColor Gray -NoNewline
                Write-Host "winget source update --force" -ForegroundColor White -NoNewline
                Write-Host "' to rebuild it." -ForegroundColor Gray
                Write-Host ""
            }
        }

        # Determine MatchOption: Param overrides Config overrides Default
        $matchOptionEnum = "ContainsCaseInsensitive"
        if ($MatchOption) {
            $matchOptionEnum = $MatchOption
        }
        else {
            try {
                $configPath = Join-Path (Get-WingetBatchConfigDir) "config.json"
                if (Test-Path $configPath) {
                    $config = Get-Content $configPath -Raw | ConvertFrom-Json
                    if ($config.SearchMatchOption) {
                        $matchOptionEnum = $config.SearchMatchOption
                    }
                }
            } catch { }
        }

        # Output intent
        if ($Query) {
            Write-Host "Searching for packages matching: " -ForegroundColor Cyan -NoNewline
            Write-Host ($Query -join ", ") -ForegroundColor Yellow
        }
        if ($Id) {
            Write-Host "Searching for exact IDs: " -ForegroundColor Cyan -NoNewline
            Write-Host ($Id -join ", ") -ForegroundColor Yellow
        }
    }

    process {
        if (-not $Query -and -not $Id) {
            Write-Error "You must provide either a search query or a specific package ID."
            return
        }

        $allPackages = [System.Collections.Generic.List[Object]]::new()

        # Handle Explicit IDs
        if ($Id) {
            foreach ($i in $Id) {
                if ([string]::IsNullOrWhiteSpace($i)) { continue }
                Write-Host "Resolving ID: " -ForegroundColor Cyan -NoNewline
                Write-Host $i -ForegroundColor Yellow

                try {
                    $comArgs = @{ Id = $i; Count = $LimitResult; ErrorAction = 'Stop' }
                    if ($Source) { $comArgs.Source = $Source }
                    
                    $comResults = Microsoft.WinGet.Client\Find-WinGetPackage @comArgs
                    foreach ($result in $comResults) {
                        $allPackages.Add([PSCustomObject]@{
                            Id = $result.Id; Name = $result.Name
                            Version = if ($result.Version) { $result.Version } else { "Unknown" }
                            Source = if ($result.Source) { $result.Source } else { "Unknown" }
                            SearchTerm = $i
                        })
                    }
                } catch { Write-Warning "Failed to search for ID: $i" }
            }
        }

        # Handle Query searches
        if ($Query) {
            $searchQueries = $Query | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' }

            foreach ($q in $searchQueries) {
                $q = $q.Trim()
                if ([string]::IsNullOrWhiteSpace($q)) { continue }

                Write-Host "Searching for: " -ForegroundColor Cyan -NoNewline
                Write-Host $q -ForegroundColor Yellow

                $searchWords = $q -split '\s+' | Where-Object { $_ -ne '' }
                $queryPackages = [System.Collections.Generic.List[PSCustomObject]]::new()

                try {
                    $comArgs = @{ Count = $LimitResult; ErrorAction = 'Stop'; MatchOption = $matchOptionEnum }
                    if ($Source) { $comArgs.Source = $Source }

                    $comResults = @()

                    if ($q -match '^\d+$') {
                        # Smart Routing: Pure numbers bypass ID to prevent garbage matches, but retain Name, Tag, and Moniker
                        $nameArgs = $comArgs.Clone()
                        $nameArgs.Name = $q
                        $tagArgs = $comArgs.Clone()
                        $tagArgs.Tag = $q
                        $monikerArgs = $comArgs.Clone()
                        $monikerArgs.Moniker = $q

                        $comResults += Microsoft.WinGet.Client\Find-WinGetPackage @nameArgs
                        $comResults += Microsoft.WinGet.Client\Find-WinGetPackage @tagArgs
                        $comResults += Microsoft.WinGet.Client\Find-WinGetPackage @monikerArgs
                    }
                    else {
                        # Standard OR routing (Name, ID, Moniker, Tags)
                        $comArgs.Query = $q
                        $comResults = Microsoft.WinGet.Client\Find-WinGetPackage @comArgs
                    }

                    foreach ($result in $comResults) {
                        if (-not $result) { continue }
                        $packageId = $result.Id
                        $packageName = $result.Name
                        $packageVersion = if ($result.Version) { $result.Version } else { "Unknown" }
                        $packageSource = if ($result.Source) { $result.Source } else { "Unknown" }

                        # If multiple search words, filter to only packages matching ALL words
                        if ($searchWords.Count -gt 1) {
                            $matchesAll = $true
                            $combinedText = "$packageName $packageId"
                            foreach ($word in $searchWords) {
                                if ($combinedText.IndexOf($word, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                                    $matchesAll = $false; break
                                }
                            }
                            if ($matchesAll) {
                                $queryPackages.Add([PSCustomObject]@{ Id = $packageId; Name = $packageName; Version = $packageVersion; Source = $packageSource; SearchTerm = $q })
                            }
                        }
                        else {
                            $queryPackages.Add([PSCustomObject]@{ Id = $packageId; Name = $packageName; Version = $packageVersion; Source = $packageSource; SearchTerm = $q })
                        }
                    }
                }
                catch { Write-Warning "Failed to search for query: $q" }

                if ($queryPackages.Count -gt 0) {
                    $allPackages.AddRange([array]$queryPackages)
                } else {
                    Write-Warning "No packages found matching '$q'"
                }
            }
        }

        # Deduplicate all collected packages based on Id (preserving order)
        $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $uniquePackages = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($pkg in $allPackages) {
            if ($seenIds.Add([string]$pkg.Id)) {
                $uniquePackages.Add($pkg)
            }
        }
        $foundPackages = $uniquePackages

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

        # Interactive Selection using PwshSpectreConsole
        if ($IWantToLiterallyInstallAllFuckingResults -or $Silent) {
            $packagesToInstall = $foundPackages.Id
        }
        elseif (-not $Silent -and (Get-Module -Name PwshSpectreConsole)) {
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

        if (-not ($Silent -or $IWantToLiterallyInstallAllFuckingResults) -and $packagesToInstall.Count -gt 0) {
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
                        Name = (ConvertTo-SpectreEscaped $item.Name)
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

                $fallbackList = $summaryList | Select-Object Name, Id, Version, Source, Publisher, SearchTerm

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
                $installParams = @{
                    Id = $packageId
                    ErrorAction = 'Stop'
                }
                if ($PSBoundParameters.ContainsKey('Mode')) { $installParams['Mode'] = $Mode }
                if ($PSBoundParameters.ContainsKey('Scope')) { $installParams['Scope'] = $Scope }
                if ($PSBoundParameters.ContainsKey('Architecture')) { $installParams['Architecture'] = $Architecture }
                if ($PSBoundParameters.ContainsKey('Override')) { $installParams['Override'] = $Override }
                if ($PSBoundParameters.ContainsKey('Location')) { $installParams['Location'] = $Location }
                if ($Force) { $installParams['Force'] = $true }
                if ($SkipDependencies) { $installParams['SkipDependencies'] = $true }
                if ($AllowHashMismatch) { $installParams['AllowHashMismatch'] = $true }

                Microsoft.WinGet.Client\Install-WinGetPackage @installParams | Out-Null
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

