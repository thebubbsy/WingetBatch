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
        [string]$SearchTerm,

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
        Write-Host $SearchTerm -ForegroundColor Yellow
    }

    process {
        # Parse individual search words for wildcard searching
        $searchWords = $SearchTerm -split '\s+' | Where-Object { $_ -ne '' }

        # Combine all search results from each word
        $allSearchResults = @()

        foreach ($word in $searchWords) {
            try {
                $wordResults = winget search $word --accept-source-agreements 2>&1

                if ($LASTEXITCODE -eq 0) {
                    $allSearchResults += $wordResults
                }
            }
            catch {
                Write-Warning "Failed to search for word: $word"
            }
        }

        if ($allSearchResults.Count -eq 0) {
            Write-Error "Error searching for packages."
            return
        }

        $searchResults = $allSearchResults -join "`n"

        # Parse the search results to extract package IDs
        $lines = $searchResults -split "`n"
        $packageIds = @()
        $headerFound = $false
        $nameColEnd = -1
        $idColStart = -1
        $idColEnd = -1

        foreach ($line in $lines) {
            # Find the header line to determine column positions
            if ($line -match '^Name\s+Id\s+') {
                $nameColEnd = $line.IndexOf('Id') - 1
                $idColStart = $line.IndexOf('Id')
                # Find where Version starts (end of Id column)
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
                # Extract the entire line for filtering and the ID
                $endPos = if ($idColEnd -lt $line.Length) { $idColEnd } else { $line.Length }
                $packageId = $line.Substring($idColStart, $endPos - $idColStart).Trim()

                # Only add if it looks like a valid package ID
                if ($packageId -and $packageId -match '^[A-Za-z0-9\.\-_]+$' -and $packageId -notmatch '^\d+\.\d+') {
                    # If multiple search words, filter to only packages matching ALL words (case-insensitive)
                    if ($searchWords.Count -gt 1) {
                        $matchesAll = $true
                        foreach ($word in $searchWords) {
                            if ($line -notmatch "(?i)$([regex]::Escape($word))") {
                                $matchesAll = $false
                                break
                            }
                        }
                        if ($matchesAll) {
                            $packageIds += $packageId
                        }
                    }
                    else {
                        $packageIds += $packageId
                    }
                }
            }
        }

        if ($packageIds.Count -eq 0) {
            Write-Warning "No packages found matching '$SearchTerm'"
            return
        }

        Write-Host "`nFound " -ForegroundColor Green -NoNewline
        Write-Host "$($packageIds.Count)" -ForegroundColor White -NoNewline
        Write-Host " package(s)" -ForegroundColor Green

        if ($WhatIf) {
            Write-Host "`n[WhatIf] Would display interactive selection for:" -ForegroundColor Yellow
            $packageIds | ForEach-Object {
                Write-Host "  • " -ForegroundColor Cyan -NoNewline
                Write-Host $_ -ForegroundColor White
            }
            return
        }

        # Interactive selection using Spectre Console
        if (-not $Silent -and (Get-Module -Name PwshSpectreConsole)) {
            Write-Host ""

            try {
                # Create multi-selection prompt
                $selectedPackages = Read-SpectreMultiSelection -Title "[cyan]Select packages to install[/]" `
                    -Choices $packageIds `
                    -PageSize 20 `
                    -Color "Green"

                if ($selectedPackages.Count -eq 0) {
                    Write-Host "`nNo packages selected. Exiting." -ForegroundColor Yellow
                    return
                }

                # Update packageIds to only selected ones
                $packageIds = $selectedPackages

                Write-Host "`nSelected " -ForegroundColor Green -NoNewline
                Write-Host "$($packageIds.Count)" -ForegroundColor White -NoNewline
                Write-Host " package(s) for installation" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to show interactive selection. Falling back to confirmation prompt."
                Write-Host "`nPackages to install:" -ForegroundColor Cyan
                $packageIds | ForEach-Object {
                    Write-Host "  • " -ForegroundColor Cyan -NoNewline
                    Write-Host $_ -ForegroundColor White
                }
                Write-Host "`nPress any key to continue with installation or Ctrl+C to cancel..." -ForegroundColor Yellow
                try {
                    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                }
                catch {
                    Write-Warning "Unable to read key input. Proceeding with installation..."
                }
            }
        }
        elseif (-not $Silent) {
            # Fallback for when Spectre Console is not available
            Write-Host "`nPackages to install:" -ForegroundColor Cyan
            $packageIds | ForEach-Object {
                Write-Host "  • " -ForegroundColor Cyan -NoNewline
                Write-Host $_ -ForegroundColor White
            }
            Write-Host "`nPress any key to continue with installation or Ctrl+C to cancel..." -ForegroundColor Yellow
            try {
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            catch {
                Write-Warning "Unable to read key input. Proceeding with installation..."
            }
        }

        Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
        Write-Host "Starting Installation Process" -ForegroundColor Cyan
        Write-Host ("=" * 60) -ForegroundColor Cyan

        $successCount = 0
        $failCount = 0

        foreach ($packageId in $packageIds) {
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
        [string]$GitHubToken
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

        $newPackages = @()
        $processedPackages = @{}
        $allCommits = @()
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
                    $allCommits += $pageCommits
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
                try {
                    # Add to list first with placeholder URL
                    $newPackages += [PSCustomObject]@{
                        Name = $packageName
                        Version = $version
                        Date = if ($commit.commit.author -and $commit.commit.author.date) { $commit.commit.author.date } else { (Get-Date).ToString('o') }
                        Link = $null  # Will be filled later
                        Message = $message.Split("`n")[0]
                        Author = if ($commit.commit.author -and $commit.commit.author.name) { $commit.commit.author.name } else { "Unknown" }
                        SHA = if ($commit.sha) { $commit.sha.Substring(0, [Math]::Min(7, $commit.sha.Length)) } else { "Unknown" }
                    }
                    $processedPackages[$packageName] = $true
                }
                catch {
                    # Skip malformed commits
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
            Write-Warning "No new packages found in the last $timeDesc. Try increasing the time period."
            if ($PSCmdlet.ParameterSetName -eq 'Hours') {
                Write-Host "Tip: Try " -NoNewline -ForegroundColor DarkGray
                Write-Host "Get-WingetNewPackages -Days 7" -ForegroundColor Yellow
            }
            return
        }

        Write-Host "`nFound " -ForegroundColor Green -NoNewline
        Write-Host "$($newPackages.Count)" -ForegroundColor White -NoNewline
        Write-Host " new package(s):" -ForegroundColor Green
        Write-Host ""

        # Display results in a formatted table
        $newPackages | Format-Table -AutoSize -Property @(
            @{Label='Package Name'; Expression={$_.Name}}
            @{Label='Version'; Expression={$_.Version}}
            @{Label='Date Added'; Expression={([DateTime]$_.Date).ToString('yyyy-MM-dd HH:mm')}}
        )

        # Interactive selection using Spectre Console
        if (Get-Module -Name PwshSpectreConsole) {
            Write-Host ""

            try {
                # Create choices with package name and version for display
                $choices = $newPackages | ForEach-Object {
                    "$($_.Name) (v$($_.Version))"
                }

                # Show multi-selection prompt
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

                    # Display links for selected packages
                    Write-Host "📦 Package Details (Ctrl+Click to open):" -ForegroundColor Cyan
                    foreach ($pkgId in $packagesToInstall) {
                        $pkgInfo = $newPackages | Where-Object { $_.Name -eq $pkgId } | Select-Object -First 1
                        Write-Host "   • " -ForegroundColor DarkGray -NoNewline
                        Write-Host "$($pkgInfo.Name)" -ForegroundColor White -NoNewline
                        Write-Host " - " -ForegroundColor DarkGray -NoNewline
                        Write-Host "$($pkgInfo.Link)" -ForegroundColor Blue
                    }
                    Write-Host ""

                    # Ask if user wants to proceed with installation
                    Write-Host "Press " -NoNewline -ForegroundColor Yellow
                    Write-Host "Enter" -NoNewline -ForegroundColor White
                    Write-Host " to continue with installation, or " -NoNewline -ForegroundColor Yellow
                    Write-Host "Ctrl+C" -NoNewline -ForegroundColor Red
                    Write-Host " to cancel..." -ForegroundColor Yellow
                    try {
                        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                    }
                    catch {
                        Write-Warning "Unable to read key input. Proceeding with installation..."
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
                }
            }
            catch {
                Write-Warning "Interactive selection unavailable. Use 'winget install <PackageName>' to install."
            }
        }
        else {
            Write-Host "`nTo install a package: " -ForegroundColor Cyan -NoNewline
            Write-Host "winget install " -ForegroundColor White -NoNewline
            Write-Host "<PackageName>" -ForegroundColor Yellow

            Write-Host "Note: Install PwshSpectreConsole for interactive package selection." -ForegroundColor DarkGray
        }

        # Track GitHub API usage
        Update-GitHubApiUsage -RequestCount ($page - 1)
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
            $rateLimitData = Get-Content $rateLimitFile | ConvertFrom-Json
            $lastReset = [DateTime]::Parse($rateLimitData.LastReset)

            # Reset counter if more than 1 hour has passed
            if (($now - $lastReset).TotalHours -ge 1) {
                $rateLimitData.RequestCount = $RequestCount
                $rateLimitData.LastReset = $now.ToString('o')
            }
            else {
                $rateLimitData.RequestCount += $RequestCount
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

    # Save updated data
    $rateLimitData | ConvertTo-Json | Out-File -FilePath $rateLimitFile -Encoding UTF8 -Force

    return $rateLimitData
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
            $rateLimitData = Get-Content $rateLimitFile | ConvertFrom-Json
            $lastReset = [DateTime]::Parse($rateLimitData.LastReset)
            $now = Get-Date

            # If more than 1 hour has passed, return 0
            if (($now - $lastReset).TotalHours -ge 1) {
                return 0
            }

            return $rateLimitData.RequestCount
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
            $installedPackages = @()

            $headerFound = $false
            foreach ($line in $installedLines) {
                if ($line -match '^-+') {
                    $headerFound = $true
                    continue
                }

                if ($headerFound -and $line.Trim() -ne '' -and $line -match '\S') {
                    # Try to extract package ID
                    if ($line -match '([A-Za-z0-9\.\-_]+\.[A-Za-z0-9\.\-_]+)\s+.*<\s*(.+?)\s*>') {
                        $installedPackages += @{
                            Id = $matches[1].Trim()
                            InstalledVersion = $matches[2].Trim()
                        }
                    }
                }
            }

            # Get list of packages with updates available
            $upgradeOutput = winget upgrade --disable-interactivity 2>&1 | Out-String
            $upgradeLines = $upgradeOutput -split "`n"
            $updatesAvailable = @()

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

                        $updatesAvailable += @{
                            Id = $packageId
                            CurrentVersion = $installedVer
                        }
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
        $updatesAvailable = @()
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
                        $updatesAvailable += @{
                            Id = $packageId
                            DisplayLine = $line.Trim()
                        }
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

        $installedPackages = @()
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
                        $installedPackages += @{
                            Id = $packageId
                            Name = $packageName
                            InstallDate = $installDate
                            DisplayLine = $line.Trim()
                        }
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

function Update-GitHubApiUsage {
    <#
    .SYNOPSIS
        Track GitHub API usage internally.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$RequestCount
    )

    $configDir = Join-Path $env:USERPROFILE ".wingetbatch"
    $usageFile = Join-Path $configDir "github_api_usage.json"

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Load existing usage data
    $usage = @{
        Requests = @()
    }

    if (Test-Path $usageFile) {
        try {
            $usage = Get-Content $usageFile | ConvertFrom-Json
            if (-not $usage.Requests) {
                $usage.Requests = @()
            }
        }
        catch {
            $usage = @{ Requests = @() }
        }
    }

    # Add current request
    $usage.Requests += @{
        Timestamp = (Get-Date).ToString('o')
        Count = $RequestCount
    }

    # Remove requests older than 1 hour
    $oneHourAgo = (Get-Date).AddHours(-1)
    $usage.Requests = $usage.Requests | Where-Object {
        try {
            [DateTime]::Parse($_.Timestamp) -ge $oneHourAgo
        }
        catch {
            $false
        }
    }

    # Save updated usage
    $usage | ConvertTo-Json | Out-File -FilePath $usageFile -Encoding UTF8 -Force

    # Calculate total requests in last hour
    $totalRequests = ($usage.Requests | Measure-Object -Property Count -Sum).Sum

    # Determine limit based on whether we have a token
    $token = Get-WingetBatchGitHubToken
    $limit = if ($token) { 5000 } else { 60 }
    $remaining = $limit - $totalRequests

    # Display usage info
    Write-Host ""
    Write-Host "GitHub API Usage (last hour): " -ForegroundColor Cyan -NoNewline
    Write-Host "$totalRequests" -ForegroundColor White -NoNewline
    Write-Host " / " -ForegroundColor DarkGray -NoNewline
    Write-Host "$limit" -ForegroundColor White -NoNewline
    Write-Host " requests" -ForegroundColor Cyan
    Write-Host "Remaining: " -ForegroundColor Cyan -NoNewline

    if ($remaining -lt 10) {
        Write-Host "$remaining" -ForegroundColor Red
    }
    elseif ($remaining -lt 50) {
        Write-Host "$remaining" -ForegroundColor Yellow
    }
    else {
        Write-Host "$remaining" -ForegroundColor Green
    }
}

# Export module members (public functions only)
# Internal functions: Get-WingetBatchGitHubToken, Start-WingetUpdateCheck, Update-GitHubApiUsage
Export-ModuleMember -Function Install-WingetAll, Get-WingetNewPackages, `
    Set-WingetBatchGitHubToken, New-WingetBatchGitHubToken, `
    Enable-WingetUpdateNotifications, Disable-WingetUpdateNotifications, `
    Get-WingetUpdates, Remove-WingetRecent
