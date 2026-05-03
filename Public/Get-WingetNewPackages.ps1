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
        [string]$ExcludeTerm,

        [Parameter()]
        [switch]$IWantToLiterallyInstallAllFuckingResults,

        [Parameter()]
        [switch]$ExportHtml
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

        $newPackages = [System.Collections.Generic.List[PSCustomObject]]::new()
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
        Write-Host "[API] GitHub API: " -ForegroundColor Cyan -NoNewline
        Write-Host "$apiRequestsMade" -ForegroundColor White -NoNewline
        Write-Host " requests made | " -ForegroundColor DarkGray -NoNewline
        Write-Host "$totalUsage" -ForegroundColor $(if ($totalUsage -gt ($limit * 0.8)) { "Red" } elseif ($totalUsage -gt ($limit * 0.5)) { "Yellow" } else { "Green" }) -NoNewline
        Write-Host "/$limit" -ForegroundColor DarkGray -NoNewline
        Write-Host " used this hour" -ForegroundColor DarkGray
        Write-Host ""
                            Write-Host "  - " -ForegroundColor Green -NoNewline
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

                            Write-Host "  - " -ForegroundColor Green -NoNewline
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
        Write-Host ""
        Write-Host "[WAIT] Fetching detailed package information in background..." -ForegroundColor DarkGray

        $configDir = Get-WingetBatchConfigDir
        $maxConcurrentJobs = 10
        $allPackageIds = @($newPackages | ForEach-Object { $_.Name })

        # Load cache to reduce API calls and IO
        $cacheFile = Join-Path $configDir "package_cache.json"
        $localCache = @{}
        if (Test-Path $cacheFile) {
            try {
                $json = Get-Content $cacheFile -Raw | ConvertFrom-Json
                if ($json -is [PSCustomObject]) {
                    $json.PSObject.Properties | ForEach-Object { $localCache[$_.Name] = $_.Value }
                }
            } catch {
                Write-Verbose "Failed to load cache: $_"
            }
        }

        # Filter packages to identify what needs fetching
        $packagesToFetchList = [System.Collections.Generic.List[string]]::new()
        $cachedResults = @{}

        foreach ($pkgId in $allPackageIds) {
            $isCached = $false
            if ($localCache.ContainsKey($pkgId)) {
                $entry = $localCache[$pkgId]
                if ($entry.CachedDate) {
                    try {
                        $cachedDate = [DateTime]$entry.CachedDate
                        # Check if fresh (< 30 days)
                        if ((Get-Date) -lt $cachedDate.AddDays(30)) {
                            $cachedResults[$pkgId] = $entry.Details
                            $isCached = $true
                        }
                    } catch {}
                }
            }

            if (-not $isCached) {
                $packagesToFetchList.Add($pkgId)
            }
        }

        $packagesToFetch = $packagesToFetchList.ToArray()
        $totalPackagesToFetch = $packagesToFetch.Count

        $packagesPerJob = if ($totalPackagesToFetch -gt 0) { [Math]::Ceiling($totalPackagesToFetch / $maxConcurrentJobs) } else { 0 }
        $actualJobCount = [Math]::Min($maxConcurrentJobs, $totalPackagesToFetch)

        $jobs = [System.Collections.Generic.List[Object]]::new()
        $jobPackageMap = @{}

        if ($cachedResults.Count -gt 0) {
            Write-Host "[OK] Found $($cachedResults.Count) packages in cache" -ForegroundColor Green
        }

        for ($i = 0; $i -lt $actualJobCount; $i++) {
            $startIndex = $i * $packagesPerJob
            $endIndex = [Math]::Min($startIndex + $packagesPerJob - 1, $totalPackagesToFetch - 1)
            $packageBatch = $packagesToFetch[$startIndex..$endIndex]

            $job = Start-WingetBatchJob -ScriptBlock {
                param($packageList, $cacheDir, $ParseSB)
                $results = @{}

                # Define Parse-WingetShowOutput in the job scope from the passed script block
                if ($ParseSB) {
                    Set-Item -Path function:Parse-WingetShowOutput -Value $ParseSB
                }

                foreach ($packageId in $packageList) {
                    # Fetch from winget
                    $output = winget show --id $packageId 2>&1 | Out-String

                    # Parse winget show output - capture ALL available fields
                    $info = Parse-WingetShowOutput -Output $output -PackageId $packageId

                    $results[$packageId] = $info
                }

                return $results
            } -ArgumentList (,$packageBatch), $configDir, $function:Parse-WingetShowOutput

            $jobs.Add($job)
            $jobPackageMap[$job.Id] = $packageBatch
        }

        Write-Host "   Started $actualJobCount background jobs processing $totalPackagesToFetch packages..." -ForegroundColor DarkGray
        Write-Host "   (~$packagesPerJob packages per job)" -ForegroundColor DarkGray

        if ($ExportHtml) {
            Write-Host "
[HTML] Exporting HTML report..." -ForegroundColor Cyan
            $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $defaultPath = "C:\temp\WingetBatch_New Packages_$timestamp.html".Replace(' ', '_')
            $exportPath = Read-Host "Enter path for HTML report [Default: $defaultPath]"
            if (-not $exportPath) { $exportPath = $defaultPath }
            if (-not $exportPath.EndsWith(".html")) { $exportPath += ".html" }
            
            try {
                Export-WingetHtmlReport -Data $newPackages -ReportTitle "New Packages" -OutFile $exportPath
                if (Test-Path $exportPath) {
                    Write-Host "[OK] Report successfully saved to $exportPath" -ForegroundColor Green
                    Invoke-Item $exportPath
                }
            } catch {
                Write-Host "[FAIL] Failed to generate HTML report: $_" -ForegroundColor Red
            }
        }

        # Interactive selection using Spectre Console
        if ($IWantToLiterallyInstallAllFuckingResults -or (Get-Module -Name PwshSpectreConsole)) {
            Write-Host ""

            try {
                # Create choices with package name and version for display
                $choices = $newPackages | ForEach-Object {
                    "$($_.Name) (v$($_.Version))"
                }

                if ($IWantToLiterallyInstallAllFuckingResults) {
                    Write-Host "Aggressive Install Mode Activated! Selecting ALL packages..." -ForegroundColor Magenta
                    $selectedChoices = $choices
                } else {
                    # Show multi-selection prompt (while jobs run in background)
                    $selectedChoices = Read-SpectreMultiSelection -Title "[cyan]Select packages to install (Space to toggle, Enter to confirm)[/]" `
                        -Choices $choices `
                        -PageSize 20 `
                        -Color "Green"
                }

                if ($selectedChoices.Count -gt 0) {
                            Write-Host "  - " -ForegroundColor Green -NoNewline
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
                        Write-Host "[WAIT] Waiting for $($runningRelevantJobs.Count) background jobs with selected packages..." -ForegroundColor DarkGray
                        $timeout = 30
                        $runningRelevantJobs | Wait-Job -Timeout $timeout | Out-Null
                    }
                    else {
                        Write-Host "[OK] Selected package details already fetched!" -ForegroundColor Green
                    }

                    # Stop irrelevant jobs immediately (user doesn't need them)
                    if ($irrelevantJobs.Count -gt 0) {
                        Write-Host "   Stopping $($irrelevantJobs.Count) irrelevant jobs..." -ForegroundColor DarkGray
                        $irrelevantJobs | Stop-Job -ErrorAction SilentlyContinue | Out-Null
                    }

                    # Collect results from relevant jobs only (each job returns a hashtable of multiple packages)
                    $allPackageDetails = @{}

                    # Add cached results first
                    foreach ($key in $cachedResults.Keys) {
                        $allPackageDetails[$key] = $cachedResults[$key]
                    }

                    $newResults = @{}

                    foreach ($job in $relevantJobs) {
                        if ($job.State -eq 'Completed') {
                            $jobResults = Receive-Job -Job $job
                            # Merge job results into master hashtable
                            foreach ($key in $jobResults.Keys) {
                                $allPackageDetails[$key] = $jobResults[$key]
                                $newResults[$key] = $jobResults[$key]
                            }
                        }
                        Remove-Job -Job $job -Force
                    }

                    # Update cache with new results
                    if ($newResults.Count -gt 0) {
                        foreach ($key in $newResults.Keys) {
                            $localCache[[string]$key] = @{
                                CachedDate = (Get-Date).ToString('o')
                                Details = $newResults[$key]
                            }
                        }

                        try {
                            $jsonContent = $localCache | ConvertTo-Json -Depth 10 -Compress:$false
                            [System.IO.File]::WriteAllText($cacheFile, $jsonContent, [System.Text.Encoding]::UTF8)
                        } catch {
                            Write-Verbose "Failed to save cache: $_"
                        }
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

                    Show-WingetPackageDetails -PackageIds $packagesToInstall -DetailsMap $packageDetails -FallbackInfo $newPackages

                    # Ask user what to do next
                    $userChoice = $null
                    if ($IWantToLiterallyInstallAllFuckingResults) {
                        $userChoice = "Install selected packages"
                    }
                    elseif (Get-Module -Name PwshSpectreConsole) {
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
                        Write-Host "[!] NOTE: All selections will be cleared when returning to the menu." -ForegroundColor Yellow
                        Write-Host "   You will need to re-select your packages." -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "Previously selected packages:" -ForegroundColor Cyan
                        foreach ($pkg in $packagesToInstall) {
                            Write-Host "  - " -ForegroundColor Green -NoNewline
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

                            Write-Host "  - " -ForegroundColor Green -NoNewline
                            Write-Host "$($packagesToInstallIds.Count)" -ForegroundColor White -NoNewline
                            Write-Host " package(s)" -ForegroundColor Green
                            Write-Host ""

                            # Fetch details for newly selected packages (from cache or jobs)
                            Write-Host "[WAIT] Fetching package details..." -ForegroundColor DarkGray

                            # Load cache once before the loop to avoid repeated I/O
                            $cacheFile = Join-Path $configDir "package_cache.json"
                            $cache = $null
                            if (Test-Path $cacheFile) {
                                try {
                                    $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
                                } catch { }
                            }

                            $reselectedPackageDetails = @{}
                            foreach ($pkgId in $packagesToInstallIds) {
                                # Check if we already have it in packageDetails
                                if ($packageDetails.ContainsKey($pkgId)) {
                                    $reselectedPackageDetails[$pkgId] = $packageDetails[$pkgId]
                                }
                                else {
                                    # Try to get from cache
                                    $cached = $null

                                    if ($null -ne $cache) {
                                        try {
                                            $packageProperty = $cache.PSObject.Properties[$pkgId]
                                            if ($packageProperty) {
                                                $packageCache = $packageProperty.Value
                                                $cachedDate = [DateTime]$packageCache.CachedDate
                                                $daysSinceCached = ((Get-Date) - $cachedDate).TotalDays

                                                if ($daysSinceCached -lt 30) {
                                                    $cached = $packageCache.Details
                                                }
                                            }
                                        } catch { }
                                    }

                                    if ($cached) {
                                        $reselectedPackageDetails[$pkgId] = $cached
                                    }
                                    else {
                                        # Fetch from winget
                                        Write-Host "  Fetching $pkgId..." -ForegroundColor DarkGray
                                        $output = winget show --id $pkgId 2>&1 | Out-String

                                        # Parse winget show output
                                        $info = Parse-WingetShowOutput -Output $output -PackageId $pkgId

                                        Set-PackageDetailsCache -PackageId $pkgId -Details $info
                                        $reselectedPackageDetails[$pkgId] = $info
                                    }
                                }
                            }

                            $packagesToInstall = $packagesToInstallIds

                            # Re-display detailed info for new selection
                            Write-Host ""
                            Show-WingetPackageDetails -PackageIds $packagesToInstall -DetailsMap $reselectedPackageDetails -FallbackInfo $newPackages

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
                            Write-Host "[OK] Successfully installed " -ForegroundColor Green -NoNewline
                            Write-Host $packageId -ForegroundColor White
                            $successCount++
                        }
                        else {
                            Write-Host "[FAIL] Failed to install " -ForegroundColor Red -NoNewline
                            Write-Host $packageId -ForegroundColor White -NoNewline
                            Write-Host " (Exit code: $LASTEXITCODE)" -ForegroundColor Red
                            $failCount++
                        }
                    }

                    Write-Host "`n" + ("=" * 60) -ForegroundColor Green
                    Write-Host "Installation Complete" -ForegroundColor Green
                    Write-Host ("=" * 60) -ForegroundColor Green
                            Write-Host "  - " -ForegroundColor Green -NoNewline
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
            Write-Host "`nâ”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”" -ForegroundColor Yellow
            Write-Host "[!] GitHub API Rate Limit Exceeded" -ForegroundColor Yellow
            Write-Host "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Unauthenticated requests are limited to 60 per hour." -ForegroundColor White
            Write-Host ""
            Write-Host "To get higher limits (5,000 requests/hour):" -ForegroundColor Cyan
            Write-Host "  1. Run: " -NoNewline -ForegroundColor White
            Write-Host "New-WingetBatchGitHubToken" -ForegroundColor Yellow
            Write-Host "     (Interactive wizard to create and save a token)" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "Or wait an hour and try again with a shorter time period." -ForegroundColor DarkGray
            Write-Host "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”" -ForegroundColor Yellow
        }
    }
}



