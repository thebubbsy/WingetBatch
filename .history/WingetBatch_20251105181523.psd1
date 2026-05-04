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
    CompanyName = 'Personal'

    # Copyright statement for this module
    Copyright = '(c) 2025. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Batch installation utilities for Windows Package Manager (winget). Search and install packages, check for updates with notifications, discover new packages from GitHub, and more.'

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
        'New-WingetBatchGitHubToken'
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
            Tags = @('winget', 'package-manager', 'windows', 'batch-install', 'utility')

            # ReleaseNotes of this module
            ReleaseNotes = 'Initial release with Install-WingetAll function for batch package installation.'
        }
    }
}
