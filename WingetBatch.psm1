1<#
.SYNOPSIS
    WingetBatch - Batch installation utilities for Windows Package Manager (winget)

.DESCRIPTION
    This module provides batch installation functionality for winget, allowing you to
    search for packages and install all matching results with a single command.

.NOTES
    Author: Matthew Bubb
    Created: November 2, 2025
#>

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
            $normalizedQuery = ($query -split '\s+') -join ' '

            # Combine all search results from each word
            $querySearchResults = [System.Collections.Generic.List[string]]::new()

            try {
                $wordResults = winget search $query --accept-source-agreements 2>&1

                if ($LASTEXITCODE -eq 0) {
                    $querySearchResults += $wordResults
                }
            }
            catch {
                Write-Warning "Failed to search for query: $query"
            }

            if ($querySearchResults.Count -eq 0) {
                continue
            }

            $searchResults = $querySearchResults -join "`n"

            # Parse the search results to extract package IDs and Names
            $lines = $searchResults -split "`n"
            $queryPackages = [System.Collections.Generic.List[PSCustomObject]]::new()

            # Pre-calculate regex patterns for filtering to improve performance
            $searchPatterns = if ($searchWords.Count -gt 1) {
                $searchWords | ForEach-Object { "(?i)$([regex]::Escape($_))" }
            } else { $null }

            $headerFound = $false
            $nameColEnd = -1
            $idColStart = -1
            $idColEnd = -1
            $versionColStart = -1
            $sourceColStart = -1
            $matchColStart = -1

            foreach ($line in $lines) {
                # Find the header line to determine column positions
                if ($line -match '^Name\s+Id\s+') {
                    $nameColEnd = $line.IndexOf('Id') - 1
                    $idColStart = $line.IndexOf('Id')

                    # Reset
                    $versionColStart = -1
                    $sourceColStart = -1
                    $matchColStart = -1

                    # Find Version
                    if ($line -match 'Version') {
                        $idColEnd = $line.IndexOf('Version') - 1
                        $versionColStart = $line.IndexOf('Version')
                    } else {
                        $idColEnd = $line.Length
                    }

                    # Find Match
                    if ($line -match 'Match') {
                        $matchColStart = $line.IndexOf('Match')
                    }

                    # Find Source
                    if ($line -match 'Source') {
                        $sourceColStart = $line.IndexOf('Source')
                    }
                    continue
                }

                # Skip until we find the header separator line (dashes)
                if ($line -match '^-+') {
                    $headerFound = $true
                    continue
                }

                if ($headerFound -and $line.Trim() -ne '' -and $idColStart -gt 0 -and $line.Length -gt $idColStart) {
                    # Extract the entire line for filtering and the ID
                    $endPos = if ($idColEnd -lt $line.Length) { $idColEnd } else { $line.Length }
                    $packageId = $line.Substring($idColStart, $endPos - $idColStart).Trim()

                    # Extract Name
                    $packageName = if ($nameColEnd -gt 0 -and $line.Length -gt $nameColEnd) {
                        $line.Substring(0, $nameColEnd).Trim()
                    } else {
                        $packageId # Fallback
                    }

                    # Extract Version
                    $packageVersion = "Unknown"
                    if ($versionColStart -gt -1 -and $line.Length -gt $versionColStart) {
                        $vEnd = $line.Length
                        # If Match is present
                        if ($matchColStart -gt $versionColStart) {
                            $vEnd = $matchColStart
                        }
                        # If Source is present (and no Match or Match is after Source)
                        elseif ($sourceColStart -gt $versionColStart) {
                            $vEnd = $sourceColStart
                        }

                        if ($vEnd -gt $line.Length) { $vEnd = $line.Length }
                        $packageVersion = $line.Substring($versionColStart, $vEnd - $versionColStart).Trim()
                    }

                    # Extract Source
                    $packageSource = "Unknown"
                    if ($sourceColStart -gt -1 -and $line.Length -gt $sourceColStart) {
                        $packageSource = $line.Substring($sourceColStart).Trim()
                    }

                    # Only add if it looks like a valid package ID
                    if ($packageId -and $packageId -match '^[A-Za-z0-9\.\-_]+$' -and $packageId -notmatch '^\d+\.\d+') {
                        # If multiple search words, filter to only packages matching ALL words (case-insensitive)
                        if ($searchWords.Count -gt 1) {
                            $matchesAll = $true
                            foreach ($pattern in $searchPatterns) {
                                if ($line -notmatch $pattern) {
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
            }

            # Deduplicate packages within this query based on Id (preserving order)
            $uniqueQueryPackages = $queryPackages | Group-Object Id | ForEach-Object { $_.Group[0] }
            $allPackages.AddRange([array]$uniqueQueryPackages)
        }

        # Keep all packages (including potential duplicates across queries) for display
        $foundPackages = $allPackages

        if ($foundPackages.Count -eq 0) {
            Write-Warning "No packages found matching '$($SearchTerms -join ", ")'"
            return
        }

        Write-Host "`nFound " -ForegroundColor Green -NoNewline
        Write-Host "$($foundPackages.Count)" -ForegroundColor White -NoNewline
        Write-Host " package(s)" -ForegroundColor Green

        if ($WhatIf) {
            Write-Host "`n[WhatIf] Would display interactive selection for:" -ForegroundColor Yellow
            $foundPackages | Group-Object SearchTerm | ForEach-Object {
                Write-Host "$($_.Name):" -ForegroundColor Yellow
                $_.Group | ForEach-Object {
                    Write-Host "  • " -ForegroundColor Cyan -NoNewline
                    Write-Host "$($_.Name) ($($_.Id))" -ForegroundColor White -NoNewline
                    if ($_.Version -ne "Unknown") {
                        Write-Host " v$($_.Version)" -ForegroundColor Green -NoNewline
                    }
                    if ($_.Source) {
                        $sColor = if ($_.Source -match 'msstore') { "Magenta" } else { "Cyan" }
                        Write-Host " [$($_.Source)]" -ForegroundColor $sColor
                    } else { Write-Host "" }
                }
            }
            return
        }

        # Prepare choices for selection with SearchTerm grouping prefix
        $packageChoices = $foundPackages | ForEach-Object {
            $sourceColor = if ($_.Source -match 'msstore') { "magenta" } else { "cyan" }
            $versionStr = if ($_.Version -ne "Unknown") { " [green]v$($_.Version)[/]" } else { "" }

            $term = ConvertTo-SpectreEscaped $_.SearchTerm
            $name = ConvertTo-SpectreEscaped $_.Name
            $id = ConvertTo-SpectreEscaped $_.Id
            $source = ConvertTo-SpectreEscaped $_.Source

            "[yellow][[$term]][/] $name ($id)$versionStr [$sourceColor]$source[/]"
        }

        # Create a lookup map
        $packageMap = @{}
        foreach ($pkg in $foundPackages) {
            $sourceColor = if ($pkg.Source -match 'msstore') { "magenta" } else { "cyan" }
            $versionStr = if ($pkg.Version -ne "Unknown") { " [green]v$($pkg.Version)[/]" } else { "" }

            $term = ConvertTo-SpectreEscaped $pkg.SearchTerm
            $name = ConvertTo-SpectreEscaped $pkg.Name
            $id = ConvertTo-SpectreEscaped $pkg.Id
            $source = ConvertTo-SpectreEscaped $pkg.Source

            $key = "[yellow][[$term]][/] $name ($id)$versionStr [$sourceColor]$source[/]"
            $packageMap[$key] = $pkg.Id
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
                Write-Error "Failed to show interactive selection. $_"
                return
            }
        }
        elseif (-not $Silent) {
            # Fallback for when Spectre Console is not available
            Write-Host "`nPackages to install:" -ForegroundColor Cyan
            $foundPackages | Group-Object SearchTerm | ForEach-Object {
                Write-Host "$($_.Name):" -ForegroundColor Yellow
                $_.Group | ForEach-Object {
                    Write-Host "  • " -ForegroundColor Cyan -NoNewline
                    Write-Host "$($_.Name) ($($_.Id))" -ForegroundColor White -NoNewline
                    if ($_.Version -ne "Unknown") {
                        Write-Host " v$($_.Version)" -ForegroundColor Green -NoNewline
                    }
                    if ($_.Source) {
                        $sColor = if ($_.Source -match 'msstore') { "Magenta" } else { "Cyan" }
                        Write-Host " [$($_.Source)]" -ForegroundColor $sColor
                    } else { Write-Host "" }
                }
            }
            Write-Host "`nPress any key to continue with installation or Ctrl+C to cancel..." -ForegroundColor Yellow
            try {
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            catch {
                Write-Warning "Unable to read key input. Proceeding with installation..."
            }
            $packagesToInstall = $foundPackages.Id
        }
        else {
             # Silent mode
             $packagesToInstall = $foundPackages.Id
        }

        Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
        Write-Host "Starting Installation Process" -ForegroundColor Cyan
        Write-Host ("=" * 60) -ForegroundColor Cyan

        $successCount = 0
        $failCount = 0

        # Deduplicate IDs to ensure we don't install the same package twice
        $uniquePackagesToInstall = $packagesToInstall | Select-Object -Unique

        foreach ($packageId in $uniquePackagesToInstall) {
            # Find info for better display (use first match from foundPackages)
            $pkgInfo = $foundPackages | Where-Object { $_.Id -eq $packageId } | Select-Object -First 1

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

            winget install --id $packageId --accept-package-agreements --accept-source-agreements --silent | Out-Null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ Successfully installed " -ForegroundColor Green -NoNewline
                Write-Host $packageId -ForegroundColor White
                $successCount++
            }
            else {
                Write-Host "✗ Failed to install " -ForegroundColor Red -NoNewline
                Write-Host $packageId -ForegroundColor White -NoNewline
                Write-Host " (Exit code: $LASTEXITCODE)" -ForegroundColor Red
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

function Get-WingetNewPackages {
    <#
    .SYNOPSIS
        Get recently added NEW packages from the winget repository.

    .DESCRIPTION
        Queries the winget-pkgs GitHub repository to find packages that were recently
        added (not just updated) to the winget library. This function fetches ALL
        commits from the specified time period with no artificial limits.

    .PARAMETER Hours
        Number of hours to look back for new packages. Default is 12 hours.
        Use this for recent checks to conserve API requests.

    .PARAMETER Days
        Number of days to look back for new packages.
        Cannot be used with -Hours parameter.

    .PARAMETER GitHubToken
        Optional GitHub Personal Access Token for authentication.
        If not provided, will use stored token from Set-WingetBatchGitHubToken.

    .PARAMETER ExcludeTerm
        Exclude packages whose names contain this term (case-insensitive).
        Useful for filtering out packages from specific publishers.

    .EXAMPLE
        Get-WingetNewPackages
        Gets all packages added in the last 12 hours (default).

    .EXAMPLE
        Get-WingetNewPackages -Hours 24
        Gets all packages added in the last 24 hours.

    .EXAMPLE
        Get-WingetNewPackages -Days 7
        Gets all packages added in the last 7 days.

    .EXAMPLE
        Get-WingetNewPackages -Days 30
        Gets all packages added in the last 30 days.

    .EXAMPLE
        Get-WingetNewPackages -Days 30 -ExcludeTerm "Microsoft"
        Gets packages from the last 30 days, excluding any with "Microsoft" in the name.

    .LINK
        https://github.com/microsoft/winget-pkgs
    #>

    [CmdletBinding(DefaultParameterSetName='Hours')]
    param(
        [Parameter(ParameterSetName='Hours')]
        [int]$Hours = 12,

        [Parameter(ParameterSetName='Days')]
        [int]$Days,

        [Parameter()]
        [string]$GitHubToken,

        [Parameter()]
        [string]$ExcludeTerm
    )

    # Ensure PwshSpectreConsole is available
    if (-not (Get-Module -Name PwshSpectreConsole)) {
        if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }
    }

    # Determine time period
    if ($PSCmdlet.ParameterSetName -eq 'Days') {
        $timeSpan = [TimeSpan]::FromDays($Days)
        $timeDesc = "$Days day$(if ($Days -ne 1) { 's' })"
    }
    else {
        $timeSpan = [TimeSpan]::FromHours($Hours)
        $timeDesc = "$Hours hour$(if ($Hours -ne 1) { 's' })"
    }

    Write-Host "Searching for packages added to winget in the last " -ForegroundColor Cyan -NoNewline
    Write-Host $timeDesc -ForegroundColor Yellow -NoNewline
    Write-Host "..." -ForegroundColor Cyan

    try {
        # Calculate the date threshold
        $since = (Get-Date).Subtract($timeSpan).ToString("yyyy-MM-ddTHH:mm:ssZ")

        $newPackages = [System.Collections.Generic.List[Object]]::new()
        $processedPackages = @{}
        $allCommits = [System.Collections.Generic.List[Object]]::new()
        $page = 1
        $perPage = 100

        # Prepare headers with optional GitHub token for higher rate limits
        $headers = @{
            'User-Agent' = 'PowerShell-WingetBatch'
            'Accept' = 'application/vnd.github.v3+json'
        }

        # Try to get stored token if not provided
        if (-not $GitHubToken) {
            $GitHubToken = Get-WingetBatchGitHubToken
        }

        # Show current API usage before starting
        $currentUsage = Get-GitHubApiRequestCount
        $limit = if ($GitHubToken) { 5000 } else { 60 }

        if ($GitHubToken) {
            $headers['Authorization'] = "Bearer $GitHubToken"
            Write-Host "Using stored GitHub token (5,000 req/hour) - " -ForegroundColor DarkGray -NoNewline
            Write-Host "$currentUsage" -ForegroundColor Cyan -NoNewline
            Write-Host " requests used this hour" -ForegroundColor DarkGray
        }
        else {
            Write-Host "No GitHub token (60 req/hour limit) - " -ForegroundColor DarkGray -NoNewline
            Write-Host "$currentUsage" -ForegroundColor Yellow -NoNewline
            Write-Host " requests used this hour" -ForegroundColor DarkGray
            Write-Host "Tip: Run " -NoNewline -ForegroundColor DarkGray
            Write-Host "New-WingetBatchGitHubToken" -NoNewline -ForegroundColor Yellow
            Write-Host " to avoid rate limits" -ForegroundColor DarkGray
        }

        # Fetch commits with pagination - NO LIMITS!
        Write-Host "Fetching commits from winget-pkgs repository..." -ForegroundColor Cyan

        $apiRequestsMade = 0
        $fetchMore = $true
        while ($fetchMore) {
            $apiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/commits?since=$since&per_page=$perPage&page=$page"

            try {
                $pageCommits = Invoke-RestMethod -Uri $apiUrl -Headers $headers
                $apiRequestsMade++

                if ($pageCommits.Count -eq 0) {
                    $fetchMore = $false
                }
                else {
                    $allCommits.AddRange(@($pageCommits))
                    Write-Host "  Fetched page $page - " -ForegroundColor DarkGray -NoNewline
                    Write-Host "$($allCommits.Count)" -ForegroundColor White -NoNewline
                    Write-Host " commits so far..." -ForegroundColor DarkGray
                    $page++

                    # If we got less than perPage, we're done
                    if ($pageCommits.Count -lt $perPage) {
                        $fetchMore = $false
                    }
                }
            }
            catch {
                Write-Warning "Failed to fetch page $page : $_"
                $fetchMore = $false
            }
        }

        # Update API request counter and get total usage
        $rateLimitData = Update-GitHubApiRequestCount -RequestCount $apiRequestsMade
        $totalUsage = $rateLimitData.RequestCount

        # Show final API usage
        Write-Host ""
        Write-Host "📊 GitHub API: " -ForegroundColor Cyan -NoNewline
        Write-Host "$apiRequestsMade" -ForegroundColor White -NoNewline
        Write-Host " requests made | " -ForegroundColor DarkGray -NoNewline
        Write-Host "$totalUsage" -ForegroundColor $(if ($totalUsage -gt ($limit * 0.8)) { "Red" } elseif ($totalUsage -gt ($limit * 0.5)) { "Yellow" } else { "Green" }) -NoNewline
        Write-Host "/$limit" -ForegroundColor DarkGray -NoNewline
        Write-Host " used this hour" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Fetched total of " -ForegroundColor Green -NoNewline
        Write-Host "$($allCommits.Count)" -ForegroundColor White -NoNewline
        Write-Host " commits" -ForegroundColor Green

        if ($allCommits.Count -eq 0) {
            Write-Warning "No commits found in the last $Days days. The winget-pkgs repository might have no recent activity."
            return
        }

        # Analyze commits for new package additions
        Write-Host "`nAnalyzing commits for new package additions..." -ForegroundColor Cyan
        Write-Host ""

        # Process commits directly
        $i = 0
        foreach ($commit in $allCommits) {
            # Null checks
            if (-not $commit.commit -or -not $commit.commit.message) {
                continue
            }

            $message = $commit.commit.message

            # Skip removal/deletion commits, updates, moves, and automatic updates
            if ($message -match '^(Remove|Delete|Deprecat|Update:|New version:|Automatic|Move)') {
                continue
            }

            # Extract package name and version
            $packageName = $null
            $version = $null

            # Pattern 1: "New package: PackageName version X.X.X"
            if ($message -match '^New package:\s*(.+?)\s+version\s+(.+?)(\s+\(#|\s*$)') {
                $packageName = $matches[1].Trim()
                $version = $matches[2].Trim()
            }
            # Pattern 2: "Add: PackageName version X.X.X"
            elseif ($message -match '^Add:\s*(.+?)\s+version\s+(.+?)(\s+\(#|\s*$)') {
                $packageName = $matches[1].Trim()
                $version = $matches[2].Trim()
            }
            # Pattern 3: "PackageName version X.X.X (#PR)"
            elseif ($message -match '^([A-Za-z0-9\.\-_]+)\s+version\s+(.+?)\s+\(#\d+\)') {
                $packageName = $matches[1].Trim()
                $version = $matches[2].Trim()
            }
            # Pattern 4: "PackageName version X.X.X"
            elseif ($message -match '^([A-Za-z0-9\.\-_]+)\s+version\s+(.+?)$') {
                $packageName = $matches[1].Trim()
                $version = $matches[2].Trim()
            }

            if ($packageName -and -not $processedPackages.ContainsKey($packageName)) {
                # Check if package should be excluded
                $shouldExclude = $false
                if ($ExcludeTerm -and $packageName -match [regex]::Escape($ExcludeTerm)) {
                    $shouldExclude = $true
                }

                if (-not $shouldExclude) {
                    try {
                        # Add to list first with placeholder URL
                        $newPackages.Add([PSCustomObject]@{
                            Name = $packageName
                            Version = $version
                            Date = if ($commit.commit.author -and $commit.commit.author.date) { $commit.commit.author.date } else { (Get-Date).ToString('o') }
                            Link = $null  # Will be filled later
                            Message = $message.Split("`n")[0]
                            Author = if ($commit.commit.author -and $commit.commit.author.name) { $commit.commit.author.name } else { "Unknown" }
                            SHA = if ($commit.sha) { $commit.sha.Substring(0, [Math]::Min(7, $commit.sha.Length)) } else { "Unknown" }
                        })
                        $processedPackages[$packageName] = $true
                    }
                    catch {
                        # Skip malformed commits
                    }
                }
            }

            $i++
            if ($i % 100 -eq 0 -or $i -eq $allCommits.Count) {
                $pct = [Math]::Round(($i / $allCommits.Count) * 100)
                Write-Host "`r  Progress: $i / $($allCommits.Count) commits ($pct%)..." -NoNewline -ForegroundColor DarkGray
            }
        }
        Write-Host ""  # New line after progress

        if ($newPackages.Count -eq 0) {
            if ($ExcludeTerm) {
                Write-Warning "No new packages found in the last $timeDesc (after excluding packages with '$ExcludeTerm')."
            }
            else {
                Write-Warning "No new packages found in the last $timeDesc. Try increasing the time period."
            }
            if ($PSCmdlet.ParameterSetName -eq 'Hours') {
                Write-Host "Tip: Try " -NoNewline -ForegroundColor DarkGray
                Write-Host "Get-WingetNewPackages -Days 7" -ForegroundColor Yellow
            }
            return
        }

        Write-Host "`nFound " -ForegroundColor Green -NoNewline
        Write-Host "$($newPackages.Count)" -ForegroundColor White -NoNewline
        Write-Host " new package(s)" -NoNewline -ForegroundColor Green
        if ($ExcludeTerm) {
            Write-Host " (excluding '$ExcludeTerm')" -NoNewline -ForegroundColor Yellow
        }
        Write-Host ":" -ForegroundColor Green
        Write-Host ""

        # Display results in a formatted table
        $newPackages | Format-Table -AutoSize -Property @(
            @{Label='Package Name'; Expression={$_.Name}}
            @{Label='Version'; Expression={$_.Version}}
            @{Label='Date Added'; Expression={([DateTime]$_.Date).ToString('yyyy-MM-dd HH:mm')}}
        ) | Out-Host

        # Fetch detailed package info in parallel BEFORE showing selection UI
        # Limit to max 10 concurrent jobs to avoid overwhelming the system
        Write-Host ""
        Write-Host "⏳ Fetching detailed package information in background..." -ForegroundColor DarkGray

        $configDir = Join-Path $env:USERPROFILE ".wingetbatch"
        $maxConcurrentJobs = 10
        $packageIds = @($newPackages | ForEach-Object { $_.Name })
        $totalPackages = $packageIds.Count

        $packagesPerJob = [Math]::Ceiling($totalPackages / $maxConcurrentJobs)
        $actualJobCount = [Math]::Min($maxConcurrentJobs, $totalPackages)

        $jobs = [System.Collections.Generic.List[Object]]::new()
        $jobPackageMap = @{}

        for ($i = 0; $i -lt $actualJobCount; $i++) {
            $startIndex = $i * $packagesPerJob
            $endIndex = [Math]::Min($startIndex + $packagesPerJob - 1, $totalPackages - 1)
            $packageBatch = $packageIds[$startIndex..$endIndex]

            $job = Start-Job -ScriptBlock {
                param($packageList, $cacheDir)
                $results = @{}

                # Helper function to get cached details
                function Get-CachedDetails {
                    param($PackageId, $CacheFile)

                    if (-not (Test-Path $CacheFile)) { return $null }

                    try {
                        $cache = Get-Content $CacheFile -Raw | ConvertFrom-Json
                        $packageCache = $cache.PSObject.Properties[$PackageId]

                        if ($packageCache) {
                            $cachedDate = [DateTime]$packageCache.CachedDate
                            $daysSinceCached = ((Get-Date) - $cachedDate).TotalDays

                            if ($daysSinceCached -lt 30) {
                                return $packageCache.Details
                            }
                        }
                    }
                    catch { }

                    return $null
                }

                # Helper function to save cached details
                function Save-CachedDetails {
                    param($PackageId, $Details, $CacheFile, $CacheDir)

                    if (-not (Test-Path $CacheDir)) {
                        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
                    }

                    $cache = @{}
                    if (Test-Path $CacheFile) {
                        try {
                            $cacheJson = Get-Content $CacheFile -Raw | ConvertFrom-Json
                            $cacheJson.PSObject.Properties | ForEach-Object {
                                $cache[$_.Name] = $_.Value
                            }
                        }
                        catch { }
                    }

                    $cache[$PackageId] = @{
                        CachedDate = (Get-Date).ToString('o')
                        Details = $Details
                    }

                    try {
                        $jsonContent = $cache | ConvertTo-Json -Depth 10 -Compress:$false
                        [System.IO.File]::WriteAllText($CacheFile, $jsonContent, [System.Text.Encoding]::UTF8)
                    }
                    catch { }
                }

                $cacheFile = Join-Path $cacheDir "package_cache.json"

                foreach ($packageId in $packageList) {
                    # Try to get from cache first
                    $cachedInfo = Get-CachedDetails -PackageId $packageId -CacheFile $cacheFile

                    if ($cachedInfo) {
                        # Use cached data
                        $results[$packageId] = $cachedInfo
                        continue
                    }

                    # Not in cache, fetch from winget
                    $output = winget show --id $packageId 2>&1 | Out-String

                    # Parse winget show output - capture ALL available fields
                    $info = @{
                        Id = $packageId
                        Version = $null
                        Publisher = $null
                        PublisherName = $null
                        PublisherUrl = $null
                        PublisherGitHub = $null
                        Author = $null
                        Homepage = $null
                        Description = $null
                        Category = $null
                        Tags = @()
                        License = $null
                        LicenseUrl = $null
                        Copyright = $null
                        CopyrightUrl = $null
                        PrivacyUrl = $null
                        PackageUrl = $null
                        ReleaseNotes = $null
                        ReleaseNotesUrl = $null
                        Installer = $null
                        Pricing = $null
                        StoreLicense = $null
                        FreeTrial = $null
                        AgeRating = $null
                        Moniker = $null
                    }

                    foreach ($line in $output -split "`n") {
                        if ($line -match '^\s*Version:\s*(.+)$') { $info.Version = $matches[1].Trim() }
                        elseif ($line -match '^\s*Publisher:\s*(.+)$') {
                            $info.PublisherName = $matches[1].Trim()
                            $info.Publisher = $matches[1].Trim()
                        }
                        elseif ($line -match '^\s*Publisher Url:\s*(.+)$') {
                            $url = $matches[1].Trim()
                            $info.PublisherUrl = $url
                            # Check if it's a GitHub URL
                            if ($url -match 'github\.com/([^/]+)') {
                                $info.PublisherGitHub = $url
                            }
                        }
                        elseif ($line -match '^\s*Author:\s*(.+)$') { $info.Author = $matches[1].Trim() }
                        elseif ($line -match '^\s*Homepage:\s*(.+)$') { $info.Homepage = $matches[1].Trim() }
                        elseif ($line -match '^\s*Description:\s*(.+)$') { $info.Description = $matches[1].Trim() }
                        elseif ($line -match '^\s*Category:\s*(.+)$') { $info.Category = $matches[1].Trim() }
                        elseif ($line -match '^\s*Tags:\s*(.+)$') {
                            $tagString = $matches[1].Trim()
                            $info.Tags = $tagString -split ',\s*'
                        }
                        elseif ($line -match '^\s*License:\s*(.+)$') { $info.License = $matches[1].Trim() }
                        elseif ($line -match '^\s*License Url:\s*(.+)$') { $info.LicenseUrl = $matches[1].Trim() }
                        elseif ($line -match '^\s*Copyright:\s*(.+)$') { $info.Copyright = $matches[1].Trim() }
                        elseif ($line -match '^\s*Copyright Url:\s*(.+)$') { $info.CopyrightUrl = $matches[1].Trim() }
                        elseif ($line -match '^\s*Privacy Url:\s*(.+)$') { $info.PrivacyUrl = $matches[1].Trim() }
                        elseif ($line -match '^\s*Package Url:\s*(.+)$') { $info.PackageUrl = $matches[1].Trim() }
                        elseif ($line -match '^\s*Release Notes:\s*(.+)$') { $info.ReleaseNotes = $matches[1].Trim() }
                        elseif ($line -match '^\s*Release Notes Url:\s*(.+)$') { $info.ReleaseNotesUrl = $matches[1].Trim() }
                        elseif ($line -match '^\s*Installer Type:\s*(.+)$') { $info.Installer = $matches[1].Trim() }
                        elseif ($line -match '^\s*Pricing:\s*(.+)$') { $info.Pricing = $matches[1].Trim() }
                        elseif ($line -match '^\s*Store License:\s*(.+)$') { $info.StoreLicense = $matches[1].Trim() }
                        elseif ($line -match '^\s*Free Trial:\s*(.+)$') { $info.FreeTrial = $matches[1].Trim() }
                        elseif ($line -match '^\s*Age Rating:\s*(.+)$') { $info.AgeRating = $matches[1].Trim() }
                        elseif ($line -match '^\s*Moniker:\s*(.+)$') { $info.Moniker = $matches[1].Trim() }
                    }

                    # Save to cache
                    Save-CachedDetails -PackageId $packageId -Details $info -CacheFile $cacheFile -CacheDir $cacheDir

                    $results[$packageId] = $info
                }

                return $results
            } -ArgumentList (,$packageBatch), $configDir

            $jobs.Add($job)
            $jobPackageMap[$job.Id] = $packageBatch
        }

        Write-Host "   Started $actualJobCount background jobs processing $totalPackages packages..." -ForegroundColor DarkGray
        Write-Host "   (~$packagesPerJob packages per job)" -ForegroundColor DarkGray

        # Interactive selection using Spectre Console
        if (Get-Module -Name PwshSpectreConsole) {
            Write-Host ""

            try {
                # Create choices with package name and version for display
                $choices = $newPackages | ForEach-Object {
                    "$($_.Name) (v$($_.Version))"
                }

                # Show multi-selection prompt (while jobs run in background)
                $selectedChoices = Read-SpectreMultiSelection -Title "[cyan]Select packages to install (Space to toggle, Enter to confirm)[/]" `
                    -Choices $choices `
                    -PageSize 20 `
                    -Color "Green"

                if ($selectedChoices.Count -gt 0) {
                    Write-Host "`nSelected " -ForegroundColor Green -NoNewline
                    Write-Host "$($selectedChoices.Count)" -ForegroundColor White -NoNewline
                    Write-Host " package(s) for installation" -ForegroundColor Green
                    Write-Host ""

                    # Extract package IDs from the selections (remove version suffix)
                    $packagesToInstall = $selectedChoices | ForEach-Object {
                        if ($_ -match '^(.+?)\s+\(v') {
                            $matches[1]
                        }
                    }

                    # Determine which jobs contain the selected packages
                    Write-Host ""
                    $relevantJobs = [System.Collections.Generic.List[Object]]::new()
                    $irrelevantJobs = [System.Collections.Generic.List[Object]]::new()

                    foreach ($job in $jobs) {
                        $jobPackages = $jobPackageMap[$job.Id]
                        $hasSelectedPackage = $false

                        foreach ($selectedPkg in $packagesToInstall) {
                            if ($jobPackages -contains $selectedPkg) {
                                $hasSelectedPackage = $true
                                break
                            }
                        }

                        if ($hasSelectedPackage) {
                            $relevantJobs.Add($job)
                        }
                        else {
                            $irrelevantJobs.Add($job)
                        }
                    }

                    # Only wait for jobs that contain selected packages
                    $runningRelevantJobs = @($relevantJobs | Where-Object { $_.State -eq 'Running' })

                    if ($runningRelevantJobs.Count -gt 0) {
                        Write-Host "⏳ Waiting for $($runningRelevantJobs.Count) background jobs with selected packages..." -ForegroundColor DarkGray
                        $timeout = 30
                        $runningRelevantJobs | Wait-Job -Timeout $timeout | Out-Null
                    }
                    else {
                        Write-Host "✓ Selected package details already fetched!" -ForegroundColor Green
                    }

                    # Stop irrelevant jobs immediately (user doesn't need them)
                    if ($irrelevantJobs.Count -gt 0) {
                        Write-Host "   Stopping $($irrelevantJobs.Count) irrelevant jobs..." -ForegroundColor DarkGray
                        $irrelevantJobs | Stop-Job -ErrorAction SilentlyContinue | Out-Null
                    }

                    # Collect results from relevant jobs only (each job returns a hashtable of multiple packages)
                    $allPackageDetails = @{}
                    foreach ($job in $relevantJobs) {
                        if ($job.State -eq 'Completed') {
                            $jobResults = Receive-Job -Job $job
                            # Merge job results into master hashtable
                            foreach ($key in $jobResults.Keys) {
                                $allPackageDetails[$key] = $jobResults[$key]
                            }
                        }
                        Remove-Job -Job $job -Force
                    }

                    # Clean up irrelevant jobs
                    foreach ($job in $irrelevantJobs) {
                        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    }

                    # Fill in any missing selected packages with empty data
                    foreach ($pkgId in $packagesToInstall) {
                        if (-not $allPackageDetails.ContainsKey($pkgId)) {
                            $allPackageDetails[$pkgId] = @{ Id = $pkgId; Homepage = $null }
                        }
                    }

                    # Extract details only for selected packages
                    $packageDetails = @{}
                    foreach ($pkgId in $packagesToInstall) {
                        $packageDetails[$pkgId] = $allPackageDetails[$pkgId]
                    }

                    Write-Host ""

                    # Display detailed package information
                    Write-Host ("=" * 80) -ForegroundColor Cyan
                    Write-Host "📦 SELECTED PACKAGES - DETAILED INFORMATION" -ForegroundColor Cyan
                    Write-Host ("=" * 80) -ForegroundColor Cyan
                    Write-Host ""

                    foreach ($pkgId in $packagesToInstall) {
                        $details = $packageDetails[$pkgId]
                        $pkgInfo = $newPackages | Where-Object { $_.Name -eq $pkgId } | Select-Object -First 1

                        Write-Host "▶ " -ForegroundColor Yellow -NoNewline
                        Write-Host $pkgId -ForegroundColor White -BackgroundColor DarkBlue
                        Write-Host ""

                        # Version
                        if ($details.Version -or $pkgInfo.Version) {
                            Write-Host "  Version:        " -ForegroundColor DarkGray -NoNewline
                            Write-Host ($details.Version ?? $pkgInfo.Version) -ForegroundColor White
                        }

                        # Publisher with GitHub link if available
                        if ($details.PublisherGitHub) {
                            Write-Host "  Publisher:      " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.PublisherName -ForegroundColor White -NoNewline
                            Write-Host " (" -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.PublisherGitHub -ForegroundColor Magenta -NoNewline
                            Write-Host ")" -ForegroundColor DarkGray
                        }
                        elseif ($details.PublisherUrl) {
                            Write-Host "  Publisher:      " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.PublisherName -ForegroundColor White -NoNewline
                            Write-Host " (" -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.PublisherUrl -ForegroundColor Blue -NoNewline
                            Write-Host ")" -ForegroundColor DarkGray
                        }
                        elseif ($details.Publisher) {
                            Write-Host "  Publisher:      " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.Publisher -ForegroundColor White
                        }

                        # Author
                        if ($details.Author) {
                            Write-Host "  Author:         " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.Author -ForegroundColor White
                        }

                        # Category & Tags
                        if ($details.Category) {
                            Write-Host "  Category:       " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.Category -ForegroundColor Cyan
                        }
                        if ($details.Tags -and $details.Tags.Count -gt 0) {
                            Write-Host "  Tags:           " -ForegroundColor DarkGray -NoNewline
                            Write-Host ($details.Tags -join ", ") -ForegroundColor DarkCyan
                        }

                        # Pricing, Store License, Free Trial
                        if ($details.Pricing) {
                            Write-Host "  Pricing:        " -ForegroundColor DarkGray -NoNewline
                            $pricingColor = if ($details.Pricing -match 'Free') { "Green" } else { "Yellow" }
                            Write-Host $details.Pricing -ForegroundColor $pricingColor
                        }
                        if ($details.StoreLicense) {
                            Write-Host "  Store License:  " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.StoreLicense -ForegroundColor White
                        }
                        if ($details.FreeTrial) {
                            Write-Host "  Free Trial:     " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.FreeTrial -ForegroundColor Yellow
                        }

                        # License
                        if ($details.License) {
                            Write-Host "  License:        " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.License -ForegroundColor White
                            if ($details.LicenseUrl) {
                                Write-Host "                  " -NoNewline
                                Write-Host $details.LicenseUrl -ForegroundColor Blue
                            }
                        }

                        # Installer Type
                        if ($details.Installer) {
                            Write-Host "  Installer:      " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.Installer -ForegroundColor White
                        }

                        # Age Rating
                        if ($details.AgeRating) {
                            Write-Host "  Age Rating:     " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.AgeRating -ForegroundColor White
                        }

                        # Moniker
                        if ($details.Moniker) {
                            Write-Host "  Moniker:        " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.Moniker -ForegroundColor DarkYellow
                        }

                        # Description
                        if ($details.Description) {
                            Write-Host "  Description:    " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.Description -ForegroundColor Gray
                        }

                        # Release Notes
                        if ($details.ReleaseNotes) {
                            Write-Host "  Release Notes:  " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.ReleaseNotes -ForegroundColor DarkGray
                        }

                        # URLs
                        if ($details.Homepage) {
                            Write-Host "  Homepage:       " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.Homepage -ForegroundColor Blue
                        }
                        if ($details.PackageUrl) {
                            Write-Host "  Package URL:    " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.PackageUrl -ForegroundColor Blue
                        }
                        if ($details.ReleaseNotesUrl) {
                            Write-Host "  Release Notes:  " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.ReleaseNotesUrl -ForegroundColor Blue
                        }
                        if ($details.PrivacyUrl) {
                            Write-Host "  Privacy Policy: " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.PrivacyUrl -ForegroundColor Blue
                        }

                        # Copyright
                        if ($details.Copyright) {
                            Write-Host "  Copyright:      " -ForegroundColor DarkGray -NoNewline
                            Write-Host $details.Copyright -ForegroundColor DarkGray
                        }

                        Write-Host ""
                    }

                    Write-Host ("=" * 80) -ForegroundColor Cyan
                    Write-Host ""

                    # Ask user what to do next
                    $userChoice = $null
                    if (Get-Module -Name PwshSpectreConsole) {
                        $userChoice = Read-SpectreSelection `
                            -Title "[yellow]What would you like to do?[/]" `
                            -Choices @("Install selected packages", "Go back and change selection", "Cancel") `
                            -Color "Green"
                    }
                    else {
                        Write-Host "Options:" -ForegroundColor Yellow
                        Write-Host "  1) Install selected packages" -ForegroundColor Green
                        Write-Host "  2) Go back and change selection" -ForegroundColor Cyan
                        Write-Host "  3) Cancel" -ForegroundColor Red
                        Write-Host ""
                        $choice = Read-Host "Enter your choice (1-3)"
                        $userChoice = switch ($choice) {
                            "1" { "Install selected packages" }
                            "2" { "Go back and change selection" }
                            "3" { "Cancel" }
                            default { "Install selected packages" }
                        }
                    }

                    if ($userChoice -eq "Go back and change selection") {
                        Write-Host "`nReturning to package selection..." -ForegroundColor Cyan
                        Write-Host ""
                        Write-Host "⚠ NOTE: All selections will be cleared when returning to the menu." -ForegroundColor Yellow
                        Write-Host "   You will need to re-select your packages." -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "Previously selected packages:" -ForegroundColor Cyan
                        foreach ($pkg in $packagesToInstall) {
                            Write-Host "  • " -ForegroundColor Green -NoNewline
                            Write-Host $pkg -ForegroundColor White
                        }
                        Write-Host ""
                        Write-Host "Press any key to continue to selection menu..." -ForegroundColor DarkGray
                        try {
                            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                        }
                        catch {
                            Start-Sleep -Seconds 2
                        }
                        Write-Host ""

                        # Re-run the selection
                        try {
                            $packagesToInstall = Read-SpectreMultiSelection `
                                -Title "[cyan]Select packages to install (Space to select, Enter to confirm)[/]" `
                                -Choices $choices `
                                -PageSize 20 `
                                -Color "Green"

                            if ($packagesToInstall.Count -eq 0) {
                                Write-Host "`nNo packages selected." -ForegroundColor Yellow
                                # Clean up background jobs
                                Write-Host "Cleaning up background jobs..." -ForegroundColor DarkGray
                                $jobs | Stop-Job | Out-Null
                                $jobs | Remove-Job -Force | Out-Null
                                return
                            }

                            # Extract package IDs from selections (remove version suffix)
                            $packagesToInstallIds = $packagesToInstall | ForEach-Object {
                                if ($_ -match '^(.+?)\s+\(v') {
                                    $matches[1]
                                }
                            }

                            Write-Host "`nSelected " -ForegroundColor Green -NoNewline
                            Write-Host "$($packagesToInstallIds.Count)" -ForegroundColor White -NoNewline
                            Write-Host " package(s)" -ForegroundColor Green
                            Write-Host ""

                            # Fetch details for newly selected packages (from cache or jobs)
                            Write-Host "⏳ Fetching package details..." -ForegroundColor DarkGray

                            $reselectedPackageDetails = @{}
                            foreach ($pkgId in $packagesToInstallIds) {
                                # Check if we already have it in packageDetails
                                if ($packageDetails.ContainsKey($pkgId)) {
                                    $reselectedPackageDetails[$pkgId] = $packageDetails[$pkgId]
                                }
                                else {
                                    # Try to get from cache
                                    $cacheFile = Join-Path $configDir "package_cache.json"
                                    $cached = $null

                                    if (Test-Path $cacheFile) {
                                        try {
                                            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
                                            $packageCache = $cache.PSObject.Properties[$pkgId]

                                            if ($packageCache) {
                                                $cachedDate = [DateTime]$packageCache.CachedDate
                                                $daysSinceCached = ((Get-Date) - $cachedDate).TotalDays

                                                if ($daysSinceCached -lt 30) {
                                                    $cached = $packageCache.Details
                                                }
                                            }
                                        }
                                        catch { }
                                    }

                                    if ($cached) {
                                        $reselectedPackageDetails[$pkgId] = $cached
                                    }
                                    else {
                                        # Fetch from winget
                                        Write-Host "  Fetching $pkgId..." -ForegroundColor DarkGray
                                        $output = winget show --id $pkgId 2>&1 | Out-String

                                        $info = @{
                                            Id = $pkgId
                                            Version = $null
                                            Publisher = $null
                                            PublisherName = $null
                                            PublisherUrl = $null
                                            PublisherGitHub = $null
                                            License = $null
                                            Description = $null
                                        }

                                        foreach ($line in $output -split "`n") {
                                            if ($line -match '^\s*Version:\s*(.+)$') { $info.Version = $matches[1].Trim() }
                                            elseif ($line -match '^\s*Publisher:\s*(.+)$') {
                                                $info.PublisherName = $matches[1].Trim()
                                                $info.Publisher = $matches[1].Trim()
                                            }
                                            elseif ($line -match '^\s*Publisher Url:\s*(.+)$') {
                                                $url = $matches[1].Trim()
                                                $info.PublisherUrl = $url
                                                if ($url -match 'github\.com/([^/]+)') {
                                                    $info.PublisherGitHub = $url
                                                }
                                            }
                                            elseif ($line -match '^\s*License:\s*(.+)$') { $info.License = $matches[1].Trim() }
                                            elseif ($line -match '^\s*Description:\s*(.+)$') { $info.Description = $matches[1].Trim() }
                                        }

                                        $reselectedPackageDetails[$pkgId] = $info
                                    }
                                }
                            }

                            $packagesToInstall = $packagesToInstallIds

                            # Re-display detailed info for new selection
                            Write-Host ""
                            Write-Host ("=" * 80) -ForegroundColor Cyan
                            Write-Host "📦 SELECTED PACKAGES - DETAILED INFORMATION" -ForegroundColor Cyan
                            Write-Host ("=" * 80) -ForegroundColor Cyan
                            Write-Host ""

                            foreach ($pkgId in $packagesToInstall) {
                                $details = $reselectedPackageDetails[$pkgId]
                                $pkgInfo = $newPackages | Where-Object { $_.Name -eq $pkgId } | Select-Object -First 1

                                Write-Host "▶ " -ForegroundColor Yellow -NoNewline
                                Write-Host $pkgId -ForegroundColor White -BackgroundColor DarkBlue
                                Write-Host ""

                                if ($details.Version -or $pkgInfo.Version) {
                                    Write-Host "  Version:        " -ForegroundColor DarkGray -NoNewline
                                    Write-Host ($details.Version ?? $pkgInfo.Version) -ForegroundColor White
                                }
                                if ($details.PublisherName) {
                                    Write-Host "  Publisher:      " -ForegroundColor DarkGray -NoNewline
                                    Write-Host $details.PublisherName -ForegroundColor White
                                }
                                if ($details.License) {
                                    Write-Host "  License:        " -ForegroundColor DarkGray -NoNewline
                                    Write-Host $details.License -ForegroundColor White
                                }
                                if ($details.Description) {
                                    Write-Host "  Description:    " -ForegroundColor DarkGray -NoNewline
                                    Write-Host $details.Description -ForegroundColor Gray
                                }

                                Write-Host ""
                            }

                            Write-Host ("=" * 80) -ForegroundColor Cyan
                            Write-Host ""

                            # Ask again after re-selection
                            if (Get-Module -Name PwshSpectreConsole) {
                                $userChoice = Read-SpectreSelection `
                                    -Title "[yellow]Proceed with installation?[/]" `
                                    -Choices @("Install selected packages", "Cancel") `
                                    -Color "Green"
                            }
                            else {
                                Write-Host "Press " -NoNewline -ForegroundColor Yellow
                                Write-Host "Enter" -NoNewline -ForegroundColor White
                                Write-Host " to install, or " -NoNewline -ForegroundColor Yellow
                                Write-Host "Ctrl+C" -NoNewline -ForegroundColor Red
                                Write-Host " to cancel..." -ForegroundColor Yellow
                                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                                $userChoice = "Install selected packages"
                            }
                        }
                        catch {
                            Write-Warning "Failed to re-select packages."
                            $userChoice = "Cancel"
                        }
                    }

                    if ($userChoice -eq "Cancel") {
                        Write-Host "`nInstallation cancelled." -ForegroundColor Red
                        # Clean up background jobs
                        Write-Host "Cleaning up background jobs..." -ForegroundColor DarkGray
                        $jobs | Stop-Job | Out-Null
                        $jobs | Remove-Job -Force | Out-Null
                        return
                    }

                    Write-Host ""

                    # Install each selected package
                    Write-Host ("=" * 60) -ForegroundColor Cyan
                    Write-Host "Starting Installation Process" -ForegroundColor Cyan
                    Write-Host ("=" * 60) -ForegroundColor Cyan

                    $successCount = 0
                    $failCount = 0

                    foreach ($packageId in $packagesToInstall) {
                        Write-Host "`n>>> Installing: " -ForegroundColor Magenta -NoNewline
                        Write-Host $packageId -ForegroundColor White

                        winget install --id $packageId --accept-package-agreements --accept-source-agreements --silent | Out-Null

                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "✓ Successfully installed " -ForegroundColor Green -NoNewline
                            Write-Host $packageId -ForegroundColor White
                            $successCount++
                        }
                        else {
                            Write-Host "✗ Failed to install " -ForegroundColor Red -NoNewline
                            Write-Host $packageId -ForegroundColor White -NoNewline
                            Write-Host " (Exit code: $LASTEXITCODE)" -ForegroundColor Red
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
                else {
                    Write-Host "`nNo packages selected." -ForegroundColor Yellow
                    # Clean up background jobs since user didn't select anything
                    Write-Host "Cleaning up background jobs..." -ForegroundColor DarkGray
                    $jobs | Stop-Job | Out-Null
                    $jobs | Remove-Job -Force | Out-Null
                }
            }
            catch {
                Write-Warning "Interactive selection unavailable. Use 'winget install <PackageName>' to install."
                # Clean up background jobs on error
                if ($jobs) {
                    $jobs | Stop-Job -ErrorAction SilentlyContinue | Out-Null
                    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
        else {
            Write-Host "`nTo install a package: " -ForegroundColor Cyan -NoNewline
            Write-Host "winget install " -ForegroundColor White -NoNewline
            Write-Host "<PackageName>" -ForegroundColor Yellow

            Write-Host "Note: Install PwshSpectreConsole for interactive package selection." -ForegroundColor DarkGray

            # Clean up background jobs since interactive selection not available
            if ($jobs) {
                Write-Host "Cleaning up background jobs..." -ForegroundColor DarkGray
                $jobs | Stop-Job -ErrorAction SilentlyContinue | Out-Null
                $jobs | Remove-Job -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
    catch {
        Write-Error "Failed to fetch new packages from GitHub: $_"
        if ($_.Exception.Response.StatusCode -eq 403 -or $_ -match 'rate limit') {
            Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
            Write-Host "⚠ GitHub API Rate Limit Exceeded" -ForegroundColor Yellow
            Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Unauthenticated requests are limited to 60 per hour." -ForegroundColor White
            Write-Host ""
            Write-Host "To get higher limits (5,000 requests/hour):" -ForegroundColor Cyan
            Write-Host "  1. Run: " -NoNewline -ForegroundColor White
            Write-Host "New-WingetBatchGitHubToken" -ForegroundColor Yellow
            Write-Host "     (Interactive wizard to create and save a token)" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "Or wait an hour and try again with a shorter time period." -ForegroundColor DarkGray
            Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
        }
    }
}

function New-WingetBatchGitHubToken {
    <#
    .SYNOPSIS
        Interactive helper to create and save a GitHub Personal Access Token.

    .DESCRIPTION
        Opens GitHub token creation page and guides you through the process.
        Automatically saves the token once you paste it.

    .EXAMPLE
        New-WingetBatchGitHubToken
        Opens GitHub and helps you create a token.

    .LINK
        https://github.com/settings/tokens
    #>

    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "🔑 GitHub Token Setup Wizard" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "I'll help you create a GitHub token to avoid API rate limits." -ForegroundColor White
    Write-Host ""
    Write-Host "Benefits:" -ForegroundColor Cyan
    Write-Host "  • " -NoNewline -ForegroundColor DarkGray
    Write-Host "60 requests/hour" -NoNewline -ForegroundColor Red
    Write-Host " → " -NoNewline -ForegroundColor DarkGray
    Write-Host "5,000 requests/hour" -ForegroundColor Green
    Write-Host "  • No special permissions needed" -ForegroundColor DarkGray
    Write-Host "  • Free forever" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Press Enter to open GitHub in your browser..." -ForegroundColor Yellow
    $null = Read-Host

    # Open GitHub token creation page
    $tokenUrl = "https://github.com/settings/tokens/new?description=WingetBatch&scopes="
    Start-Process $tokenUrl

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "📋 Follow these steps on GitHub:" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. " -NoNewline -ForegroundColor Yellow
    Write-Host "The token is already named 'WingetBatch'" -ForegroundColor White
    Write-Host ""
    Write-Host "2. " -NoNewline -ForegroundColor Yellow
    Write-Host "Set expiration (or choose 'No expiration' for convenience)" -ForegroundColor White
    Write-Host ""
    Write-Host "3. " -NoNewline -ForegroundColor Yellow
    Write-Host "DON'T check any permission boxes - none needed!" -ForegroundColor White
    Write-Host ""
    Write-Host "4. " -NoNewline -ForegroundColor Yellow
    Write-Host "Click " -NoNewline -ForegroundColor White
    Write-Host "'Generate token' " -NoNewline -ForegroundColor Green
    Write-Host "at the bottom" -ForegroundColor White
    Write-Host ""
    Write-Host "5. " -NoNewline -ForegroundColor Yellow
    Write-Host "COPY the token (starts with 'ghp_')" -ForegroundColor White
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""

    # Prompt for token
    $token = Read-Host "Paste your token here (it won't be visible)"

    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Host ""
        Write-Host "❌ No token provided. Setup cancelled." -ForegroundColor Red
        Write-Host "   Run this command again when you have your token." -ForegroundColor DarkGray
        return
    }

    # Validate token format
    if ($token -notmatch '^ghp_[a-zA-Z0-9]{36}$' -and $token -notmatch '^github_pat_[a-zA-Z0-9_]+$') {
        Write-Host ""
        Write-Host "⚠️  Warning: Token format doesn't look right." -ForegroundColor Yellow
        Write-Host "   Expected format: ghp_xxxxxxxxxxxx or github_pat_xxxxxxxxxxxx" -ForegroundColor DarkGray
        Write-Host ""
        $continue = Read-Host "Continue anyway? (y/n)"
        if ($continue -ne 'y') {
            Write-Host "Setup cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Test the token
    Write-Host ""
    Write-Host "Testing token..." -ForegroundColor Cyan
    try {
        $testUrl = "https://api.github.com/user"
        $response = Invoke-RestMethod -Uri $testUrl -Headers @{
            'Authorization' = "Bearer $token"
            'User-Agent' = 'PowerShell-WingetBatch'
        } -ErrorAction Stop

        Write-Host "✓ Token is valid!" -ForegroundColor Green
        Write-Host "  Authenticated as: " -NoNewline -ForegroundColor DarkGray
        Write-Host $response.login -ForegroundColor White
    }
    catch {
        Write-Host "❌ Token test failed!" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host ""
        $continue = Read-Host "Save token anyway? (y/n)"
        if ($continue -ne 'y') {
            Write-Host "Setup cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Save token
    Set-WingetBatchGitHubToken -Token $token

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "✓ Setup Complete!" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now use all WingetBatch commands without rate limits!" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Try: " -NoNewline -ForegroundColor DarkGray
    Write-Host "Get-WingetNewPackages -Days 30" -ForegroundColor Yellow
    Write-Host ""
}

function Set-WingetBatchGitHubToken {
    <#
    .SYNOPSIS
        Set or update the GitHub Personal Access Token for API authentication.

    .DESCRIPTION
        Stores a GitHub token securely to avoid API rate limits when checking for new packages.
        Without a token, you're limited to 60 requests/hour. With a token, you get 5,000 requests/hour.

        For an interactive wizard, use New-WingetBatchGitHubToken instead.

    .PARAMETER Token
        Your GitHub Personal Access Token. Create one at https://github.com/settings/tokens
        No special permissions are required.

    .PARAMETER Remove
        Remove the stored GitHub token.

    .EXAMPLE
        Set-WingetBatchGitHubToken -Token "ghp_xxxxxxxxxxxx"
        Stores your GitHub token for future use.

    .EXAMPLE
        Set-WingetBatchGitHubToken -Remove
        Removes the stored GitHub token.

    .EXAMPLE
        New-WingetBatchGitHubToken
        Use the interactive wizard instead.

    .LINK
        https://github.com/settings/tokens
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Set')]
        [string]$Token,

        [Parameter(Mandatory=$true, ParameterSetName='Remove')]
        [switch]$Remove
    )

    $configDir = Join-Path $env:USERPROFILE ".wingetbatch"
    $tokenFile = Join-Path $configDir "github_token.txt"

    if ($Remove) {
        if (Test-Path $tokenFile) {
            Remove-Item $tokenFile -Force
            Write-Host "✓ GitHub token removed successfully" -ForegroundColor Green
        }
        else {
            Write-Host "No GitHub token found to remove" -ForegroundColor Yellow
        }
        return
    }

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Store token
    $Token | Out-File -FilePath $tokenFile -Encoding UTF8 -Force

    Write-Host "✓ GitHub token saved successfully!" -ForegroundColor Green
    Write-Host "  Location: $tokenFile" -ForegroundColor DarkGray
    Write-Host "  The token will now be used automatically for API requests." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ℹ Security Note:" -ForegroundColor Yellow
    Write-Host "  • Token stored in plain text (no permissions required for this module)" -ForegroundColor DarkGray
    Write-Host "  • Only increases API rate limits - cannot modify repositories or access private data" -ForegroundColor DarkGray
    Write-Host "  • If stolen, someone could make API requests as you (read public repos only)" -ForegroundColor DarkGray
    Write-Host "  • Revoke anytime at: https://github.com/settings/tokens" -ForegroundColor DarkGray
}

function Get-PackageDetailsCache {
    <#
    .SYNOPSIS
        Retrieve cached package details.

    .DESCRIPTION
        Internal function to get cached package details from JSON file.
        Cache expires after 30 days.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId
    )

    $cacheFile = Join-Path $env:USERPROFILE ".wingetbatch\package_cache.json"

    if (-not (Test-Path $cacheFile)) {
        return $null
    }

    try {
        $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $packageCache = $cache.PSObject.Properties[$PackageId]

        if ($packageCache) {
            $cachedDate = [DateTime]$packageCache.CachedDate
            $daysSinceCached = ((Get-Date) - $cachedDate).TotalDays

            if ($daysSinceCached -lt 30) {
                return $packageCache.Details
            }
        }
    }
    catch {
        # Ignore cache read errors
    }

    return $null
}

function Set-PackageDetailsCache {
    <#
    .SYNOPSIS
        Store package details in cache.

    .DESCRIPTION
        Internal function to cache package details to JSON file with 30-day TTL.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId,

        [Parameter(Mandatory=$true)]
        [hashtable]$Details
    )

    $configDir = Join-Path $env:USERPROFILE ".wingetbatch"
    $cacheFile = Join-Path $configDir "package_cache.json"

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Load existing cache or create new
    $cache = @{}
    if (Test-Path $cacheFile) {
        try {
            $cacheJson = Get-Content $cacheFile -Raw | ConvertFrom-Json
            # Convert PSCustomObject to hashtable
            $cacheJson.PSObject.Properties | ForEach-Object {
                $cache[$_.Name] = $_.Value
            }
        }
        catch {
            # Start fresh if cache is corrupt
        }
    }

    # Add/update package entry
    $cache[$PackageId] = @{
        CachedDate = (Get-Date).ToString('o')
        Details = $Details
    }

    # Save cache
    try {
        $jsonContent = $cache | ConvertTo-Json -Depth 10 -Compress:$false
        [System.IO.File]::WriteAllText($cacheFile, $jsonContent, [System.Text.Encoding]::UTF8)
    }
    catch {
        Write-Verbose "Failed to write package cache: $_"
    }
}

function Get-WingetBatchGitHubToken {
    <#
    .SYNOPSIS
        Retrieve the stored GitHub token.

    .DESCRIPTION
        Internal function to get the stored GitHub token for API authentication.

    .OUTPUTS
        String - The GitHub token if found, otherwise $null
    #>

    [CmdletBinding()]
    param()

    $tokenFile = Join-Path $env:USERPROFILE ".wingetbatch\github_token.txt"

    if (Test-Path $tokenFile) {
        return (Get-Content $tokenFile -Raw).Trim()
    }

    return $null
}

function Update-GitHubApiRequestCount {
    <#
    .SYNOPSIS
        Track GitHub API requests per hour.

    .DESCRIPTION
        Internal function to track and display GitHub API request usage.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$RequestCount = 1
    )

    $configDir = Join-Path $env:USERPROFILE ".wingetbatch"
    $rateLimitFile = Join-Path $configDir "github_ratelimit.json"

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $now = Get-Date

    # Load or create rate limit tracking data
    if (Test-Path $rateLimitFile) {
        try {
            $jsonData = Get-Content $rateLimitFile -Raw | ConvertFrom-Json
            $lastReset = [DateTime]$jsonData.LastReset

            # Reset counter if more than 1 hour has passed
            if (($now - $lastReset).TotalHours -ge 1) {
                $rateLimitData = @{
                    RequestCount = $RequestCount
                    LastReset = $now.ToString('o')
                }
            }
            else {
                # Accumulate requests - ensure we're working with integers
                $currentCount = [int]$jsonData.RequestCount
                $rateLimitData = @{
                    RequestCount = $currentCount + $RequestCount
                    LastReset = $jsonData.LastReset
                }
            }
        }
        catch {
            # If file is corrupt, create new
            $rateLimitData = @{
                RequestCount = $RequestCount
                LastReset = $now.ToString('o')
            }
        }
    }
    else {
        $rateLimitData = @{
            RequestCount = $RequestCount
            LastReset = $now.ToString('o')
        }
    }

    # Save updated data - ensure JSON is written properly
    $jsonContent = $rateLimitData | ConvertTo-Json -Compress:$false
    [System.IO.File]::WriteAllText($rateLimitFile, $jsonContent, [System.Text.Encoding]::UTF8)

    return [PSCustomObject]$rateLimitData
}

function Get-GitHubApiRequestCount {
    <#
    .SYNOPSIS
        Get current GitHub API request count for this hour.

    .DESCRIPTION
        Returns the number of GitHub API requests made in the current hour.
    #>

    [CmdletBinding()]
    param()

    $rateLimitFile = Join-Path $env:USERPROFILE ".wingetbatch\github_ratelimit.json"

    if (Test-Path $rateLimitFile) {
        try {
            $rateLimitData = Get-Content $rateLimitFile -Raw | ConvertFrom-Json
            $lastReset = [DateTime]$rateLimitData.LastReset
            $now = Get-Date

            # If more than 1 hour has passed, return 0
            if (($now - $lastReset).TotalHours -ge 1) {
                return 0
            }

            return [int]$rateLimitData.RequestCount
        }
        catch {
            return 0
        }
    }

    return 0
}

function Enable-WingetUpdateNotifications {
    <#
    .SYNOPSIS
        Enable automatic winget update notifications in your PowerShell profile.

    .DESCRIPTION
        Adds a background check to your PowerShell profile that monitors for winget package updates.
        The check runs when you open a terminal and can optionally run on an interval.

    .PARAMETER Interval
        How often to check for updates (in hours). Default is 3 hours.
        Set to 0 to only check when opening a new terminal.

    .PARAMETER CheckOnStartup
        Check for updates every time you open a terminal. Default is $true.

    .EXAMPLE
        Enable-WingetUpdateNotifications
        Enables update notifications with default settings (check on startup and every 3 hours).

    .EXAMPLE
        Enable-WingetUpdateNotifications -Interval 6
        Check every 6 hours instead of 3.

    .EXAMPLE
        Enable-WingetUpdateNotifications -Interval 0 -CheckOnStartup $true
        Only check when opening a terminal, not on an interval.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Interval = 3,

        [Parameter()]
        [bool]$CheckOnStartup = $true
    )

    $configDir = Join-Path $env:USERPROFILE ".wingetbatch"
    $configFile = Join-Path $configDir "config.json"

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Save configuration
    $config = @{
        UpdateNotificationsEnabled = $true
        CheckInterval = $Interval
        CheckOnStartup = $CheckOnStartup
        LastCheck = $null
    }

    $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force

    # Add to PowerShell profile
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue

    $initCode = @'

# WingetBatch - Update Notifications
if (Get-Module -ListAvailable -Name WingetBatch) {
    Import-Module WingetBatch -ErrorAction SilentlyContinue
    Start-WingetUpdateCheck
}
'@

    if ($profileContent -notmatch 'Start-WingetUpdateCheck') {
        Add-Content -Path $profilePath -Value $initCode
        Write-Host "✓ Update notifications enabled!" -ForegroundColor Green
        Write-Host "  Configuration saved to: $configFile" -ForegroundColor DarkGray
        Write-Host "  Profile updated: $profilePath" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Restart your terminal or run: " -NoNewline -ForegroundColor Cyan
        Write-Host ". `$PROFILE" -ForegroundColor Yellow
    }
    else {
        Write-Host "✓ Configuration updated!" -ForegroundColor Green
        Write-Host "  Update notifications were already enabled in your profile." -ForegroundColor DarkGray
    }
}

function Disable-WingetUpdateNotifications {
    <#
    .SYNOPSIS
        Disable automatic winget update notifications.

    .DESCRIPTION
        Removes the update check from your PowerShell profile and disables notifications.

    .EXAMPLE
        Disable-WingetUpdateNotifications
        Disables update notifications.
    #>

    [CmdletBinding()]
    param()

    $configDir = Join-Path $env:USERPROFILE ".wingetbatch"
    $configFile = Join-Path $configDir "config.json"

    # Update configuration
    if (Test-Path $configFile) {
        $config = Get-Content $configFile | ConvertFrom-Json
        $config.UpdateNotificationsEnabled = $false
        $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force
    }

    # Remove from profile
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (Test-Path $profilePath) {
        $profileContent = Get-Content $profilePath -Raw

        # Remove the WingetBatch initialization block
        $pattern = '(?s)# WingetBatch - Update Notifications.*?Start-WingetUpdateCheck\s*\}'
        $newContent = $profileContent -replace $pattern, ''

        $newContent | Out-File -FilePath $profilePath -Encoding UTF8 -Force
    }

    Write-Host "✓ Update notifications disabled" -ForegroundColor Green
    Write-Host "  Restart your terminal for changes to take effect." -ForegroundColor DarkGray
}

function Start-WingetUpdateCheck {
    <#
    .SYNOPSIS
        Internal function that runs the update check and displays notifications.

    .DESCRIPTION
        This function is called automatically from your PowerShell profile.
        It checks if updates are available and displays a notification.
    #>

    [CmdletBinding()]
    param()

    $configDir = Join-Path $env:USERPROFILE ".wingetbatch"
    $configFile = Join-Path $configDir "config.json"
    $cacheFile = Join-Path $configDir "update_cache.json"

    # Check if notifications are enabled
    if (-not (Test-Path $configFile)) {
        return
    }

    $config = Get-Content $configFile | ConvertFrom-Json

    if (-not $config.UpdateNotificationsEnabled) {
        return
    }

    # Check if we should run based on interval
    $shouldCheck = $false

    if ($config.CheckOnStartup -and -not $config.LastCheck) {
        $shouldCheck = $true
    }
    elseif ($config.LastCheck) {
        $lastCheck = [DateTime]::Parse($config.LastCheck)
        $hoursSinceCheck = ((Get-Date) - $lastCheck).TotalHours

        if ($config.CheckInterval -gt 0 -and $hoursSinceCheck -ge $config.CheckInterval) {
            $shouldCheck = $true
        }
        elseif ($config.CheckOnStartup) {
            $shouldCheck = $true
        }
    }
    else {
        $shouldCheck = $true
    }

    if (-not $shouldCheck) {
        # Load cached results if available
        if (Test-Path $cacheFile) {
            $cache = Get-Content $cacheFile | ConvertFrom-Json
            if ($cache.UpdateCount -gt 0) {
                Write-Host ""
                Write-Host "📦 " -NoNewline -ForegroundColor Cyan
                Write-Host "$($cache.UpdateCount) winget package update(s) available" -ForegroundColor Yellow
                Write-Host "   Run " -NoNewline -ForegroundColor DarkGray
                Write-Host "Get-WingetUpdates" -NoNewline -ForegroundColor White
                Write-Host " to view and install them" -ForegroundColor DarkGray
            }
        }
        return
    }

    # Run check in background job
    $job = Start-Job -ScriptBlock {
        param($configDir, $cacheFile)

        try {
            # Get list of installed packages
            $installedOutput = winget list --disable-interactivity 2>&1 | Out-String
            $installedLines = $installedOutput -split "`n"
            $installedPackages = [System.Collections.Generic.List[Object]]::new()

            $headerFound = $false
            foreach ($line in $installedLines) {
                if ($line -match '^-+') {
                    $headerFound = $true
                    continue
                }

                if ($headerFound -and $line.Trim() -ne '' -and $line -match '\S') {
                    # Try to extract package ID
                    if ($line -match '([A-Za-z0-9\.\-_]+\.[A-Za-z0-9\.\-_]+)\s+.*<\s*(.+?)\s*>') {
                        $installedPackages.Add(@{
                            Id = $matches[1].Trim()
                            InstalledVersion = $matches[2].Trim()
                        })
                    }
                }
            }

            # Get list of packages with updates available
            $upgradeOutput = winget upgrade --disable-interactivity 2>&1 | Out-String
            $upgradeLines = $upgradeOutput -split "`n"
            $updatesAvailable = [System.Collections.Generic.List[Object]]::new()

            $headerFound = $false
            foreach ($line in $upgradeLines) {
                if ($line -match '^-+') {
                    $headerFound = $true
                    continue
                }

                if ($headerFound -and $line.Trim() -ne '' -and $line -notmatch 'upgrades available') {
                    # Extract package info
                    if ($line -match '([A-Za-z0-9\.\-_]+\.[A-Za-z0-9\.\-_]+)') {
                        $packageId = $matches[1].Trim()

                        # Try to get version info
                        if ($line -match '<\s*(.+?)\s*>') {
                            $installedVer = $matches[1].Trim()
                        }
                        else {
                            $installedVer = "Unknown"
                        }

                        $updatesAvailable.Add(@{
                            Id = $packageId
                            CurrentVersion = $installedVer
                        })
                    }
                }
            }

            # Save cache
            $cache = @{
                UpdateCount = $updatesAvailable.Count
                Updates = $updatesAvailable
                LastChecked = (Get-Date).ToString('o')
            }

            $cache | ConvertTo-Json | Out-File -FilePath $cacheFile -Encoding UTF8 -Force

            return $updatesAvailable.Count

        }
        catch {
            return -1
        }
    } -ArgumentList $configDir, $cacheFile

    # Update last check time
    $config.LastCheck = (Get-Date).ToString('o')
    $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force

    # Wait briefly for job (non-blocking)
    Wait-Job -Job $job -Timeout 10 | Out-Null

    if ($job.State -eq 'Completed') {
        $updateCount = Receive-Job -Job $job

        if ($updateCount -gt 0) {
            Write-Host ""
            Write-Host "📦 " -NoNewline -ForegroundColor Cyan
            Write-Host "$updateCount winget package update(s) available" -ForegroundColor Yellow
            Write-Host "   Run " -NoNewline -ForegroundColor DarkGray
            Write-Host "Get-WingetUpdates" -NoNewline -ForegroundColor White
            Write-Host " to view and install them" -ForegroundColor DarkGray
        }
    }

    Remove-Job -Job $job -Force
}

function Get-WingetUpdates {
    <#
    .SYNOPSIS
        Check for and install available winget package updates.

    .DESCRIPTION
        Displays a list of all installed winget packages that have updates available,
        with an interactive selection to choose which ones to update.

    .PARAMETER Force
        Skip the cache and force a fresh check for updates.

    .EXAMPLE
        Get-WingetUpdates
        Shows available updates and allows you to select which to install.

    .EXAMPLE
        Get-WingetUpdates -Force
        Forces a fresh check for updates.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force
    )

    # Ensure PwshSpectreConsole is available
    if (-not (Get-Module -Name PwshSpectreConsole)) {
        if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Checking for winget package updates..." -ForegroundColor Cyan

    # Check cache first
    $cacheFile = Join-Path $env:USERPROFILE ".wingetbatch\update_cache.json"
    $useCache = $false

    if (-not $Force -and (Test-Path $cacheFile)) {
        $cache = Get-Content $cacheFile | ConvertFrom-Json
        $cacheAge = ((Get-Date) - [DateTime]::Parse($cache.LastChecked)).TotalMinutes

        if ($cacheAge -lt 30) {
            $useCache = $true
            $updatesAvailable = $cache.Updates
            Write-Host "Using cached results (checked $([Math]::Round($cacheAge, 0)) minutes ago)" -ForegroundColor DarkGray
        }
    }

    if (-not $useCache) {
        # Get list of packages with updates available
        $upgradeOutput = winget upgrade --disable-interactivity 2>&1 | Out-String
        $upgradeLines = $upgradeOutput -split "`n"
        $updatesAvailable = [System.Collections.Generic.List[Object]]::new()
        $seenIds = @{}

        $headerFound = $false
        foreach ($line in $upgradeLines) {
            if ($line -match '^-+') {
                $headerFound = $true
                continue
            }

            if ($headerFound -and $line.Trim() -ne '' -and $line -notmatch 'upgrades available' -and $line -notmatch 'package\(s\) have version') {
                # Parse the table format and extract package ID
                if ($line -match '\s+([A-Za-z][A-Za-z0-9]*\.[A-Za-z0-9][A-Za-z0-9\.\-_]*)\s+') {
                    $packageId = $matches[1].Trim()

                    # Only add if it hasn't been seen
                    if (-not $seenIds.ContainsKey($packageId)) {
                        # Store the entire line for display
                        $updatesAvailable.Add(@{
                            Id = $packageId
                            DisplayLine = $line.Trim()
                        })
                        $seenIds[$packageId] = $true
                    }
                }
            }
        }
    }

    if ($updatesAvailable.Count -eq 0) {
        Write-Host "✓ All packages are up to date!" -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "Found " -ForegroundColor Green -NoNewline
    Write-Host "$($updatesAvailable.Count)" -ForegroundColor White -NoNewline
    Write-Host " update(s) available" -ForegroundColor Green
    Write-Host ""

    # Interactive selection using Spectre Console
    if (Get-Module -Name PwshSpectreConsole) {
        try {
            # Create a lookup table: DisplayLine -> Id
            $displayToId = @{}
            $displayLines = $updatesAvailable | ForEach-Object {
                $displayToId[$_.DisplayLine] = $_.Id
                $_.DisplayLine
            }

            $selectedLines = Read-SpectreMultiSelection -Title "[cyan]Select packages to update (Space to toggle, Enter to confirm)[/]" `
                -Choices $displayLines `
                -PageSize 20 `
                -Color "Green"

            if ($selectedLines.Count -eq 0) {
                Write-Host "No packages selected." -ForegroundColor Yellow
                return
            }

            # Convert selected display lines back to package IDs
            $selectedPackages = $selectedLines | ForEach-Object { $displayToId[$_] }

            Write-Host ""
            Write-Host "Updating " -ForegroundColor Cyan -NoNewline
            Write-Host "$($selectedPackages.Count)" -ForegroundColor White -NoNewline
            Write-Host " package(s)..." -ForegroundColor Cyan
            Write-Host ""

            $successCount = 0
            $failCount = 0

            foreach ($packageId in $selectedPackages) {
                Write-Host ">>> Updating: " -ForegroundColor Magenta -NoNewline
                Write-Host $packageId -ForegroundColor White

                winget upgrade --id $packageId --accept-package-agreements --accept-source-agreements

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✓ Successfully updated " -ForegroundColor Green -NoNewline
                    Write-Host $packageId -ForegroundColor White
                    $successCount++
                }
                else {
                    Write-Host "✗ Failed to update " -ForegroundColor Red -NoNewline
                    Write-Host $packageId -ForegroundColor White
                    $failCount++
                }
                Write-Host ""
            }

            Write-Host ("=" * 60) -ForegroundColor Green
            Write-Host "Update Complete" -ForegroundColor Green
            Write-Host ("=" * 60) -ForegroundColor Green
            Write-Host "Success: " -ForegroundColor Green -NoNewline
            Write-Host $successCount -ForegroundColor White -NoNewline
            Write-Host " | Failed: " -ForegroundColor Red -NoNewline
            Write-Host $failCount -ForegroundColor White

            # Clear cache after updates
            if (Test-Path $cacheFile) {
                Remove-Item $cacheFile -Force
            }
        }
        catch {
            Write-Warning "Interactive selection error: $_"
            Write-Host "Packages with updates available:" -ForegroundColor Cyan
            $updatesAvailable | ForEach-Object {
                Write-Host "  • $($_.Id)" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "Use 'winget upgrade <PackageName>' to update manually." -ForegroundColor Yellow
            return
        }
    }
    else {
        # Fallback without interactive selection
        Write-Host "Packages with updates available:" -ForegroundColor Cyan
        $updatesAvailable | ForEach-Object {
            Write-Host "  • $($_.Id)" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "To update a package: " -ForegroundColor Cyan -NoNewline
        Write-Host "winget upgrade <PackageName>" -ForegroundColor Yellow
        Write-Host "To update all: " -ForegroundColor Cyan -NoNewline
        Write-Host "winget upgrade --all" -ForegroundColor Yellow
    }
}

function Remove-WingetRecent {
    <#
    .SYNOPSIS
        Uninstall recently installed winget packages.

    .DESCRIPTION
        Shows packages installed in the last X days and allows interactive selection
        of which packages to uninstall.

    .PARAMETER Days
        Number of days to look back for recently installed packages. Default is 1 day.

    .EXAMPLE
        Remove-WingetRecent
        Shows packages installed in the last day and allows you to select which to uninstall.

    .EXAMPLE
        Remove-WingetRecent -Days 7
        Shows packages installed in the last 7 days.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Days = 1
    )

    # Ensure PwshSpectreConsole is available
    if (-not (Get-Module -Name PwshSpectreConsole)) {
        if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Searching for packages installed in the last " -ForegroundColor Cyan -NoNewline
    Write-Host "$Days day$(if ($Days -ne 1) { 's' })..." -ForegroundColor Yellow

    try {
        Write-Host "Reading Windows Registry for installation dates..." -ForegroundColor Cyan

        # Get installation dates from Windows Registry
        $uninstallPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        $registryApps = @{}
        foreach ($path in $uninstallPaths) {
            try {
                Get-ItemProperty $path -ErrorAction SilentlyContinue | ForEach-Object {
                    $displayName = $_.DisplayName
                    $installDate = $_.InstallDate

                    if ($displayName -and $installDate) {
                        # Parse InstallDate (format: YYYYMMDD)
                        try {
                            $year = $installDate.Substring(0, 4)
                            $month = $installDate.Substring(4, 2)
                            $day = $installDate.Substring(6, 2)
                            $date = [DateTime]::ParseExact("$year-$month-$day", "yyyy-MM-dd", $null)

                            if (-not $registryApps.ContainsKey($displayName)) {
                                $registryApps[$displayName] = $date
                            }
                        }
                        catch {
                            # Skip invalid dates
                        }
                    }
                }
            }
            catch {
                # Skip inaccessible registry paths
            }
        }

        Write-Host "Found installation dates for $($registryApps.Count) programs" -ForegroundColor DarkGray
        Write-Host ""

        # Get list of installed packages from winget
        $listOutput = winget list --disable-interactivity 2>&1 | Out-String
        $listLines = $listOutput -split "`n"

        $installedPackages = [System.Collections.Generic.List[Object]]::new()
        $seenIds = @{}
        $headerFound = $false
        $idColStart = -1
        $idColEnd = -1
        $nameColEnd = -1

        $cutoffDate = (Get-Date).AddDays(-$Days).Date

        foreach ($line in $listLines) {
            # Find the header line to determine column positions
            if ($line -match '^Name\s+Id\s+') {
                $nameColEnd = $line.IndexOf('Id') - 1
                $idColStart = $line.IndexOf('Id')
                if ($line -match 'Version') {
                    $idColEnd = $line.IndexOf('Version') - 1
                } else {
                    $idColEnd = $line.Length
                }
                continue
            }

            # Skip until we find the header separator line (dashes)
            if ($line -match '^-+') {
                $headerFound = $true
                continue
            }

            if ($headerFound -and $line.Trim() -ne '' -and $idColStart -gt 0 -and $line.Length -gt $idColStart) {
                # Extract package ID and Name
                $endPos = if ($idColEnd -lt $line.Length) { $idColEnd } else { $line.Length }
                $packageId = $line.Substring($idColStart, $endPos - $idColStart).Trim()
                $packageName = if ($nameColEnd -gt 0 -and $line.Length -gt $nameColEnd) {
                    $line.Substring(0, $nameColEnd).Trim()
                } else {
                    ""
                }

                # Only process valid package IDs and avoid duplicates
                if ($packageId -and $packageId -match '^[A-Za-z0-9\.\-_]+$' -and -not $seenIds.ContainsKey($packageId)) {
                    # Try to find installation date from registry
                    $installDate = $null

                    # Try exact name match first
                    if ($registryApps.ContainsKey($packageName)) {
                        $installDate = $registryApps[$packageName]
                    }
                    else {
                        # Try fuzzy match - check if registry name contains package name or vice versa
                        foreach ($regName in $registryApps.Keys) {
                            if ($regName -match [regex]::Escape($packageName) -or $packageName -match [regex]::Escape($regName)) {
                                $installDate = $registryApps[$regName]
                                break
                            }
                        }
                    }

                    # Only add if within time window (or no date found and we show all)
                    if ($installDate -and $installDate -ge $cutoffDate) {
                        $installedPackages.Add(@{
                            Id = $packageId
                            Name = $packageName
                            InstallDate = $installDate
                            DisplayLine = $line.Trim()
                        })
                        $seenIds[$packageId] = $true
                    }
                }
            }
        }

        if ($installedPackages.Count -eq 0) {
            Write-Warning "No packages installed in the last $Days day$(if ($Days -ne 1) { 's' })."
            Write-Host "Note: Only packages with registry install dates can be tracked." -ForegroundColor DarkGray
            return
        }

        # Sort by install date (most recent first)
        $installedPackages = $installedPackages | Sort-Object -Property InstallDate -Descending

        Write-Host "Found " -ForegroundColor Green -NoNewline
        Write-Host "$($installedPackages.Count)" -ForegroundColor White -NoNewline
        Write-Host " package(s) installed in the last $Days day$(if ($Days -ne 1) { 's' })" -ForegroundColor Green
        Write-Host ""

        # Interactive selection using Spectre Console
        if (Get-Module -Name PwshSpectreConsole) {
            try {
                # Create a lookup table: DisplayLine -> Id with install date
                $displayToId = @{}
                $displayLines = $installedPackages | ForEach-Object {
                    $dateStr = $_.InstallDate.ToString('yyyy-MM-dd')
                    $displayText = "($dateStr) $($_.Id)"
                    $displayToId[$displayText] = $_.Id
                    $displayText
                }

                $selectedLines = Read-SpectreMultiSelection -Title "[red]⚠ Select packages to UNINSTALL (Space to toggle, Enter to confirm)[/]" `
                    -Choices $displayLines `
                    -PageSize 20 `
                    -Color "Red"

                if ($selectedLines.Count -eq 0) {
                    Write-Host "No packages selected." -ForegroundColor Yellow
                    return
                }

                # Convert selected display lines back to package IDs
                $selectedPackages = $selectedLines | ForEach-Object { $displayToId[$_] }

                Write-Host ""
                Write-Host "⚠ WARNING: " -ForegroundColor Red -NoNewline
                Write-Host "You are about to UNINSTALL " -ForegroundColor Yellow -NoNewline
                Write-Host "$($selectedPackages.Count)" -ForegroundColor White -NoNewline
                Write-Host " package(s):" -ForegroundColor Yellow
                Write-Host ""

                foreach ($pkgId in $selectedPackages) {
                    Write-Host "   • " -ForegroundColor Red -NoNewline
                    Write-Host $pkgId -ForegroundColor White
                }

                Write-Host ""
                Write-Host "Type " -NoNewline -ForegroundColor Yellow
                Write-Host "YES" -NoNewline -ForegroundColor Red
                Write-Host " to confirm uninstallation, or anything else to cancel: " -NoNewline -ForegroundColor Yellow
                $confirmation = Read-Host

                if ($confirmation -ne "YES") {
                    Write-Host "Uninstallation cancelled." -ForegroundColor Green
                    return
                }

                Write-Host ""
                Write-Host ("=" * 60) -ForegroundColor Red
                Write-Host "Starting Uninstallation Process" -ForegroundColor Red
                Write-Host ("=" * 60) -ForegroundColor Red
                Write-Host ""

                $successCount = 0
                $failCount = 0

                foreach ($packageId in $selectedPackages) {
                    Write-Host ">>> Uninstalling: " -ForegroundColor Magenta -NoNewline
                    Write-Host $packageId -ForegroundColor White

                    winget uninstall --id $packageId --accept-source-agreements

                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✓ Successfully uninstalled " -ForegroundColor Green -NoNewline
                        Write-Host $packageId -ForegroundColor White
                        $successCount++
                    }
                    else {
                        Write-Host "✗ Failed to uninstall " -ForegroundColor Red -NoNewline
                        Write-Host $packageId -ForegroundColor White
                        $failCount++
                    }
                    Write-Host ""
                }

                Write-Host ("=" * 60) -ForegroundColor Green
                Write-Host "Uninstallation Complete" -ForegroundColor Green
                Write-Host ("=" * 60) -ForegroundColor Green
                Write-Host "Success: " -ForegroundColor Green -NoNewline
                Write-Host $successCount -ForegroundColor White -NoNewline
                Write-Host " | Failed: " -ForegroundColor Red -NoNewline
                Write-Host $failCount -ForegroundColor White
            }
            catch {
                Write-Warning "Interactive selection error: $_"
                Write-Host "Installed packages:" -ForegroundColor Cyan
                $installedPackages | ForEach-Object {
                    Write-Host "  • $($_.Id)" -ForegroundColor White
                }
                Write-Host ""
                Write-Host "Use 'winget uninstall <PackageName>' to uninstall manually." -ForegroundColor Yellow
                return
            }
        }
        else {
            Write-Host "Installed packages:" -ForegroundColor Cyan
            $installedPackages | ForEach-Object {
                Write-Host "  • $($_.Id)" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "To uninstall a package: " -ForegroundColor Cyan -NoNewline
            Write-Host "winget uninstall <PackageName>" -ForegroundColor Yellow
            Write-Host "Note: Install PwshSpectreConsole for interactive package selection." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Error "Failed to get installed packages: $_"
    }
}

function ConvertTo-SpectreEscaped {
    <#
    .SYNOPSIS
        Escape special characters for Spectre Console markup.

    .DESCRIPTION
        Internal function to escape brackets so they are rendered literally in Spectre Console.
        [ becomes [[
        ] becomes ]]
    #>
    param(
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    return $Text -replace '\[', '[[' -replace '\]', ']]'
}

# Export module members (public functions only)
# Internal functions: Get-WingetBatchGitHubToken, Start-WingetUpdateCheck, Update-GitHubApiRequestCount
Export-ModuleMember -Function Install-WingetAll, Get-WingetNewPackages, `
    Set-WingetBatchGitHubToken, New-WingetBatchGitHubToken, `
    Enable-WingetUpdateNotifications, Disable-WingetUpdateNotifications, `
    Get-WingetUpdates, Remove-WingetRecent
