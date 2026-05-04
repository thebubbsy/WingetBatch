@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'WingetBatch.psm1'

    # Version number of this module.
    ModuleVersion = '2.0.0'

    # ID used to uniquely identify this module
    GUID = 'b9e8f5d2-4c3f-4a6b-8d9e-2f7a8b5c6e4f'

    # Author of this module
    Author = 'Matthew Bubb'

    # Company or vendor of this module
    CompanyName = 'OnYaChamp'

    # Copyright statement for this module
    Copyright = '(c) 2025 Matthew Bubb. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Advanced batch operations for Windows Package Manager (winget). Features: interactive multi-select installation, GitHub new package discovery with 30-day caching, background update monitoring with profile integration, registry-based recent package removal, API rate limiting, and comprehensive package details including pricing, licensing, and release notes. Requires PwshSpectreConsole for enhanced UI.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module
    FunctionsToExport = @(
        'Install-WingetAll',
        'Get-WingetNewPackages',
        'Get-WingetUpdates',
        'Enable-WingetUpdateNotifications',
        'Disable-WingetUpdateNotifications',
        'Set-WingetBatchGitHubToken',
        'New-WingetBatchGitHubToken',
        'Remove-WingetRecent'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for module discovery.
            Tags = @('winget', 'package-manager', 'windows', 'batch-install', 'utility', 'github-api', 'interactive', 'cache', 'updates', 'notifications')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/drbubbles-tech/WingetBatch/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/drbubbles-tech/WingetBatch'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
v2.0.0 - Major Feature Release
- NEW: Get-WingetNewPackages - Discover recently added packages from winget-pkgs GitHub repository
  * GitHub API integration with pagination support
  * Parallel background job system (max 10 concurrent) for fetching package details
  * Smart job waiting - only waits for jobs with selected packages
  * 30-day package details caching system for faster repeat searches
  * Comprehensive package info: Version, Publisher, GitHub links, License, Pricing, Release Notes, and 20+ fields
  * Interactive re-selection with preserved package information
  * Exclusion filter support to hide specific packages/publishers
  * API rate limit tracking with hourly rollover
  * GitHub token support for 5,000 req/hour (vs 60 unauthenticated)

- NEW: Remove-WingetRecent - Uninstall recently installed packages by date
  * Reads from Windows Registry (HKLM/HKCU Uninstall keys)
  * Filter by installation date (e.g., -Days 7 for last week)
  * Interactive selection of packages to remove

- ENHANCED: Install-WingetAll
  * Now uses --silent flag for cleaner output
  * Improved error handling and reporting

- ENHANCED: Profile Integration
  * Background update checks with cached results
  * 30-minute cache TTL for update notifications

- NEW: Token Management
  * Set-WingetBatchGitHubToken - Store GitHub PAT securely
  * New-WingetBatchGitHubToken - Interactive token creation wizard

- FIXED: Date parsing bug in API rate limit tracking (timezone handling)
- FIXED: Package selection workflow when going back to change selections

Configuration stored in: ~/.wingetbatch/
  - config.json - Update notification settings
  - github_token.txt - GitHub Personal Access Token
  - github_ratelimit.json - API usage tracking
  - package_cache.json - 30-day package details cache
  - update_cache.json - Cached update results

Requires: PowerShell 5.1+, winget CLI, PwshSpectreConsole (auto-installs if missing)
'@
        }
    }
}
