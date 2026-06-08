@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'WingetBatch.psm1'

    # Version number of this module.
    ModuleVersion = '2.4.5'

    # ID used to uniquely identify this module
    GUID = 'b9e8f5d2-4c3f-4a6b-8d9e-2f7a8b5c6e4f'

    # Author of this module
    Author = 'Matthew Bubb'

    # Company or vendor of this module
    CompanyName = 'OnYaChamp.com'

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
        'Remove-WingetRecent',
        'Export-WingetBatchConfig',
        'Import-WingetBatchConfig',
        'Invoke-WingetBatchCleanup',
        'Update-WingetBatch',
        'Invoke-WinGetBatch',
        'Get-WingetHoroscope',
        'Test-WingetPackageVibes',
        'Convert-WingetPackageToHaiku',
        'Show-WingetMatrix',
        'Invoke-WingetRussianRoulette'
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
            Tags = @('winget', 'package-manager', 'windows', 'batch-install', 'utility', 'github-api', 'interactive', 'cache', 'updates', 'PwshSpectreConsole')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/thebubbsy/WingetBatch/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/thebubbsy/WingetBatch'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
v2.4.0 - Security Update & Massive Feature Bloat
- FIXED: Replaced unsafe Invoke-Expression with argument array execution in Invoke-WinGetBatch.
- FIXED: Fallback PS5.1 execution for ForEach-Object -Parallel downloads.
- FIXED: Array casting fixes and character encoding parsing fixes.
- NEW: Get-WingetHoroscope - Predict the celestial fate of your package updates.
- NEW: Invoke-WingetRussianRoulette - Installs a completely random package from the Winget repository.
- NEW: Convert-WingetPackageToHaiku - Generates a 5-7-5 syllable poem for any package.
- NEW: Show-WingetMatrix - Displays your installed packages cascading down the screen like The Matrix.
- NEW: Test-WingetPackageVibes - Arbitrary algorithmic vibe check for Winget packages (Corporate = Cringe).

v2.3.0 - Next-Generation Idempotent Deployment Engine
- NEW: Invoke-WinGetBatch - Idempotent, manifest-driven package deployments using native COM APIs.
  * Decoupled from fragile CLI regex parsing; uses Microsoft.WinGet.Client COM interfaces.
  * Split-Phase Concurrency: Parallel downloads via native PowerShell 7 ForEach-Object -Parallel with serial, collision-free background installations.
  * High-fidelity target state configuration parsing from standard JSON and YAML manifests.
  * Diagnostic exit code mapping (standardizing successful exits 0, pending reboots 3010/1641, and failures).
  * Forensic and auditing: compilation of structured JSON deployment reports containing detailed per-package status telemetry.
  * Full integration with the winget batch environment and standalone distribution channels.
  * Author/Architect: Matthew Bubb. All credit for this next-generation design is attributed solely to him.

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
  * Set-WingetBatchGitHubToken - Store GitHub PAT securely (AES encrypted CliXml)
  * New-WingetBatchGitHubToken - Interactive token creation wizard with masked input

- FIXED: Date parsing bug in API rate limit tracking (timezone handling)
- FIXED: Package selection workflow when going back to change selections

Configuration stored in: ~/.wingetbatch/
  - config.json - Update notification settings
  - github_token.clixml - Secure GitHub Personal Access Token
  - github_ratelimit.json - API usage tracking
  - package_cache.json - 30-day package details cache
  - update_cache.json - Cached update results

Requires: PowerShell 5.1+, winget CLI, PwshSpectreConsole (auto-installs if missing)
'@
        }
    }
}


