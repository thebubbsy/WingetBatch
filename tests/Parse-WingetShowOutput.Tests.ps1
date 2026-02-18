Describe "Parse-WingetShowOutput" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force
    }

    It "Parses full winget show output correctly" {
        $output = @"
Found Visual Studio Code [Microsoft.VSCode]
Version: 1.95.3
Publisher: Microsoft Corporation
Publisher Url: https://www.microsoft.com/
Author: Microsoft Corporation
Moniker: vscode
Description: Visual Studio Code is a lightweight but powerful source code editor.
Homepage: https://code.visualstudio.com/
License: MIT
License Url: https://github.com/microsoft/vscode/blob/main/LICENSE.txt
Privacy Url: https://privacy.microsoft.com/en-us/privacystatement
Copyright: Copyright (C) Microsoft Corporation. All rights reserved.
Copyright Url: https://github.com/microsoft/vscode/blob/main/LICENSE.txt
Tags: development, editor, electron, ide, programming
Installer:
  Type: exe
  Locale: en-US
  Download Url: https://vscode.download.prss.microsoft.com/dbazure/download/stable/f1a4fb101478ce6ec82fe9627c43efbf9e98c813/VSCodeUserSetup-x64-1.95.3.exe
  SHA256: F058B5C085C83446051759556C075A81773A5342407513C33E609386E784332D
  Release Date: 2024-11-13
Pricing: Free
Store License: Free
Free Trial: No
Age Rating: 3+
Release Notes: https://code.visualstudio.com/updates
Release Notes Url: https://code.visualstudio.com/updates
"@

        # We need to access internal function, so we use InModuleScope or invoke via scriptblock if not exported
        # Since it is internal, we can use InModuleScope if Pester supports it for imported modules,
        # or we can dot-source the module file if it wasn't a psm1 with Export-ModuleMember.
        # But WingetBatch.psm1 has Export-ModuleMember.
        # Best way is to use & (Get-Module WingetBatch) { $function:Parse-WingetShowOutput } logic if InModuleScope is tricky.

        $module = Get-Module WingetBatch
        $result = & $module { Param($o, $id) Parse-WingetShowOutput -Output $o -PackageId $id } -o $output -id "Microsoft.VSCode"

        $result.Id | Should -Be "Microsoft.VSCode"
        $result.Version | Should -Be "1.95.3"
        $result.Publisher | Should -Be "Microsoft Corporation"
        $result.PublisherUrl | Should -Be "https://www.microsoft.com/"
        $result.Author | Should -Be "Microsoft Corporation"
        $result.Moniker | Should -Be "vscode"
        $result.Description | Should -Be "Visual Studio Code is a lightweight but powerful source code editor."
        $result.Homepage | Should -Be "https://code.visualstudio.com/"
        $result.License | Should -Be "MIT"
        $result.LicenseUrl | Should -Be "https://github.com/microsoft/vscode/blob/main/LICENSE.txt"
        $result.PrivacyUrl | Should -Be "https://privacy.microsoft.com/en-us/privacystatement"
        $result.Copyright | Should -Be "Copyright (C) Microsoft Corporation. All rights reserved."
        $result.CopyrightUrl | Should -Be "https://github.com/microsoft/vscode/blob/main/LICENSE.txt"
        $result.Tags | Should -Be "development", "editor", "electron", "ide", "programming"
        # Installer type matching logic in original code was: "Installer Type: ..." but in sample output sometimes it is "Installer:" then "Type: ..."
        # The original code only matches `^\s*Installer Type:\s*(.+)$`.
        # Wait, the sample I used in benchmark had "Installer Type: exe".
        # But `winget show` output often has nested yaml-like structure for Installer.
        # The original code: `elseif ($line -match '^\s*Installer Type:\s*(.+)$') { $info.Installer = $matches[1].Trim() }`
        # It does NOT handle the nested "Type: user" under "Installer:".
        # So my test sample should match what the code currently supports or what `winget show` actually outputs.
        # If I want to preserve existing behavior exactly, I should stick to what `Parse-WingetShowOutput` supports.
        # It supports `Installer Type: ...`.

        $result.Pricing | Should -Be "Free"
        $result.StoreLicense | Should -Be "Free"
        $result.FreeTrial | Should -Be "No"
        $result.AgeRating | Should -Be "3+"
        $result.ReleaseNotes | Should -Be "https://code.visualstudio.com/updates"
        $result.ReleaseNotesUrl | Should -Be "https://code.visualstudio.com/updates"
    }

    It "Handles GitHub Publisher URL correctly" {
        $output = "Publisher Url: https://github.com/microsoft/winget-cli"
        $module = Get-Module WingetBatch
        $result = & $module { Param($o, $id) Parse-WingetShowOutput -Output $o -PackageId $id } -o $output -id "Test"

        $result.PublisherUrl | Should -Be "https://github.com/microsoft/winget-cli"
        $result.PublisherGitHub | Should -Be "https://github.com/microsoft/winget-cli"
    }
}
