@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'WingetBatch.psm1'

    # Version number of this module.
    ModuleVersion = '2.10.0'

    # ID used to uniquely identify this module
    GUID = 'b9e8f5d2-4c3f-4a6b-8d9e-2f7a8b5c6e4f'

    # Author of this module
    Author = 'Matthew Bubb'

    # Company or vendor of this module
    CompanyName = 'OnYaChamp.com'

    # Copyright statement for this module
    Copyright = '(c) 2025-2026 Matthew Bubb. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Advanced batch operations for Windows Package Manager (winget). Features: interactive multi-select installation, GitHub new package discovery with 30-day caching, background update monitoring with profile integration, registry-based recent package removal, API rate limiting, and comprehensive package details including pricing, licensing, and release notes. Requires PwshSpectreConsole for enhanced UI.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.4'

    # PwshSpectreConsole (required) only runs on PowerShell 7.4+
    CompatiblePSEditions = @('Core')

    # Required modules
    RequiredModules = @('Microsoft.WinGet.Client', 'PwshSpectreConsole')

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
v2.10.0 - Reliability Release
- REQUIREMENT: PowerShell 7.4+ is now declared (PwshSpectreConsole already required it; 11 commands never parsed on 5.1).
- FIXED: Installs/updates/uninstalls reported success when the installer failed. WinGet returns a Status instead of throwing; every command now checks it and shows the real error and reboot requirement.
- FIXED: Modules that export the same command names (e.g. Cobalt) hijacked Get-WinGetPackage, so Get-WingetUpdates always said "up to date". All WinGet calls are now module-qualified.
- FIXED: Get-WingetMachineState failed on every call (helpers defined after use). -RemoveExtraneous now only touches WinGet-sourced packages and lists them first; pinned versions are honored; new -Force and -IncludeUnmanaged.
- FIXED: Get-WingetDependencyGraph failed on every call (wrong parameter name); tree output and Mermaid labels fixed.
- FIXED: Get-Date -ToString (invalid) broke Restore-WingetSnapshot -Take, Invoke-WingetFleet, Send-WingetWebhook (Discord), Test-WingetCompliance reports, Export-WingetOffline and the maintenance task.
- FIXED: Register-WingetMaintenance tasks never updated anything (called the interactive Get-WingetUpdates). -IncludeStore, NotifyOnly (webhooks) and Monthly schedules now work.
- FIXED: Start-WingetServer used a non-existent Pode cmdlet (Add-PodeRouteMiddleware); routes no longer call interactive commands; crypto-random API key; -Https uses a self-signed certificate.
- FIXED: Get-WingetNewPackages used local time as UTC, shifting the search window by the UTC offset; background detail jobs never received the parser, losing descriptions and licenses.
- FIXED: Get-WingetPackageInfo -ShowManifest/-ShowVersions, Get-WingetChangelog release notes and Get-WingetHealthScore manifest checks read the wrong files; version lists sorted as text (9.x above 10.x).
- FIXED: Get-WingetHealthScore flagged almost every package as pre-release ("Source" contains "rc") and scored freshness by version count; it now uses the real last-commit date.
- FIXED: Install-WingetProfile -Path could not load its own -Export output; 20 built-in profile/recommendation IDs did not exist in winget.
- FIXED: Enable-WingetUpdateNotifications overwrote config.json (losing webhooks and search settings). Config writes now merge.
- FIXED: Invoke-WinGetBatch ignored version pins and ran a download phase whose files were never used (and which always failed). -ThrottleLimit is now ignored.
- FIXED: Remove-WingetRecent could attach the wrong install date via loose name matching; now uses the COM API and exact/registry-key matching.
- FIXED: Export-WingetOffline ignored -Architecture and ran MSIs without msiexec; now built on Export-WinGetPackage with hash verification and per-installer silent switches.
- FIXED: Invoke-WingetFleet lost machine names on failure and -RetryFailed ignored -UseSSH; timeouts reported.
- FIXED: Test-WingetCompliance -NewPolicy -PolicyPath could not bind; Send-WingetWebhook -SaveConfig prompted for -Event; Teams now uses Adaptive Cards.
- FIXED: Watch-WingetPackages -Once crashed when output was redirected; showed 0 updates and misaligned borders.
- NEW: Get-WingetUpdates -ListOnly, Get-WingetHistory -PassThru, Restore-WingetSnapshot -RestoreVersions/-Force, Install-WingetProfile -Force.
- NEW: -AutoSnapshot now actually snapshots before every WingetBatch install/update/uninstall; -UndoLast 1 undoes the latest one.
- NEW: Update notifications share the update cache with Get-WingetUpdates, so it opens instantly after a background check.
- LIVE-TESTED against real installs, updates, uninstalls, downloads and a running API server. Fixes from that pass:
  * Results are verified, not trusted: an update that leaves the old version reports NotUpdated, an uninstall that leaves the program reports StillInstalled (both happen in practice with WinGet 1.30).
  * Pinning/rollback to an older version uninstalls first, then installs and verifies (installing over the top left two registered copies of VLC).
  * ARP\ and MSIX\ packages (Add/Remove Programs entries) can be updated/uninstalled; WinGet's ID search rejects those IDs.
  * Install-WingetAll -Id is an exact match (VideoLAN.VLC also installed VideoLAN.VLC.Nightly); summary table renders colors.
  * Start-WingetServer: never started ($using in the main Pode block), API-key check read a non-existent property, /api/health crashed, rate limit was per-thread, result counts were wrong. Errors now log to ~/.wingetbatch/server_errors_*.log; responses carry X-RateLimit-Remaining.
  * Invoke-WingetFleet: an edit had left the old implementation in place; machine names and per-package errors now reported.
  * Install-Offline.ps1 accepts "-PackageId a,b" from powershell.exe -File / cmd.
  * winget show parsing handles multi-line Description, Tags and Release Notes.
  * Pode/WinGet.Client/WingetBatch installs and Update-WingetBatch work with PSResourceGet without prompting.
  * Get-WingetChangelog processes every piped package ID.
- TESTS: 30 new regression tests (78 total).

Full history: https://github.com/thebubbsy/WingetBatch/blob/main/CHANGELOG.md
'@
        }
    }
}


