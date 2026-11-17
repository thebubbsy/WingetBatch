@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'WingetBatch.psm1'

    # Version number of this module.
    ModuleVersion = '2.11.0'

    # ID used to uniquely identify this module
    GUID = 'b9e8f5d2-4c3f-4a6b-8d9e-2f7a8b5c6e4f'

    # Author of this module
    Author = 'Matthew Bubb'

    # Company or vendor of this module
    CompanyName = 'OnYaChamp.com'

    # Copyright statement for this module
    Copyright = '(c) 2025-2026 Matthew Bubb. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Advanced batch operations for Windows Package Manager (winget). Features: interactive multi-select installation, GitHub new package discovery with 30-day caching, background update monitoring with profile integration, registry-based recent package removal, API rate limiting, and comprehensive package details including pricing, licensing, and release notes. Works on Windows PowerShell 5.1+ and PowerShell 7+ (optionally uses PwshSpectreConsole on PowerShell 7.4+).'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Supported PowerShell editions
    CompatiblePSEditions = @('Desktop', 'Core')

    # Required modules
    RequiredModules = @('Microsoft.WinGet.Client')

    # Functions to export from this module
    FunctionsToExport = @('Start-WingetUpdateCheck',
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
        'Set-WingetBatchConfig',
        'Get-WingetBatchConfig',
        'Invoke-WingetBatchCleanup',
        'Update-WingetBatch',
        'Invoke-WinGetBatch',
        'Repair-WingetBatchManager',
        'Get-WingetMachineState',
        'Get-WingetPackageInfo',
        'Get-WingetHistory',
        'Watch-WingetPackages',
        'Find-WingetDuplicate',
        'Register-WingetMaintenance',
        'Get-WingetDependencyGraph',
        'Start-WingetServer',
        'Get-WingetRecommend',
        'Invoke-WingetFleet',
        'Restore-WingetSnapshot',
        'Test-WingetCompliance',
        'Get-WingetHealthScore',
        'Send-WingetWebhook',
        'Export-WingetOffline',
        'Install-WingetProfile',
        'Get-WingetChangelog'
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
v2.11.0 - Windows PowerShell 5.1 Support & Background Job / Encoding Fixes
- FIXED: Hang at "Waiting for background jobs..." in Install-WingetAll and Get-WingetNewPackages. Passing a module-bound Parse-WingetShowOutput scriptblock into Start-ThreadJob deadlocked against the caller runspace waiting in Wait-Job; jobs now receive plain function source text and exact-match winget show (-e --accept-source-agreements) without nested-array wrapping on multi-package batches.
- FIXED: Eliminated the large PwshSpectreConsole Warning panel on terminals with non-UTF-8 encoding (e.g. OEM United States / CP437) by enabling UTF-8 console encoding on PowerShell 7+ and guarding PwshSpectreConsole import.
- NEW: Full Windows PowerShell 5.1 (Desktop) compatibility across the entire module so WingetBatch can install PowerShell 7 (`pwsh`) out of the box on a fresh Windows install.
  * PowerShellVersion lowered back to 5.1; CompatiblePSEditions includes Desktop and Core.
  * PwshSpectreConsole is now optional (auto-used on PowerShell 7.4+ when installed) with an interactive numbered console selection fallback (supports single items, lists, ranges like 1-3, 'all', and cancellation) in Install-WingetAll, Get-WingetUpdates, Get-WingetNewPackages, Get-WingetRecommend, and Remove-WingetRecent.
  * Removed PowerShell 7-only syntax/APIs in Test-WingetCompliance, Invoke-WingetFleet, Start-WingetServer, Register-WingetMaintenance, Send-WingetWebhook, and Install-WingetBatchDependency; added TLS 1.2 initialization on Windows PowerShell 5.1.
- FIXED: Set-PackageDetailsCache and Get-PackageDetailsCache handling of cached PSCustomObject detail entries.

Full history: https://github.com/thebubbsy/WingetBatch/blob/main/CHANGELOG.md
'@
        }
    }
}


