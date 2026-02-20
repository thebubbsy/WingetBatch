Describe "Parse-WingetShowOutput" {
    BeforeAll {
        # Dot-source the module to access internal functions
        # We need to use Import-Module to load the module properly if it exports members
        # But for testing internal functions, dot-sourcing is often required if they are not exported
        # However, Export-ModuleMember might interfere.
        # Best practice for testing internal functions is InModuleScope, but that requires the module to be imported.

        # Try to import the module
        Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force
    }

    Context "Standard Output Parsing" {
        It "Parses standard fields correctly" {
            $result = InModuleScope WingetBatch {
                $output = @"
Found MongoDB Shell [MongoDB.Shell]
Version: 2.3.2
Publisher: MongoDB, Inc.
Publisher Url: https://www.mongodb.com/
Author: MongoDB, Inc.
Moniker: mongosh
Description: The MongoDB Shell description.
Homepage: https://www.mongodb.com/try/download/shell
License: SSPL
License Url: https://www.mongodb.com/licensing/server-side-public-license
Privacy Url: https://www.mongodb.com/legal/privacy-policy
Copyright: Copyright (c) MongoDB, Inc.
Copyright Url: https://www.mongodb.com/legal/copyright
Tags: mongodb, shell, cli
Installer:
  Installer Type: wix
"@
                Parse-WingetShowOutput -Output $output -PackageId "MongoDB.Shell"
            }

            $result.Id | Should -Be "MongoDB.Shell"
            $result.Version | Should -Be "2.3.2"
            $result.Publisher | Should -Be "MongoDB, Inc."
            $result.PublisherUrl | Should -Be "https://www.mongodb.com/"
            $result.Author | Should -Be "MongoDB, Inc."
            $result.Moniker | Should -Be "mongosh"
            $result.Description | Should -Be "The MongoDB Shell description."
            $result.Homepage | Should -Be "https://www.mongodb.com/try/download/shell"
            $result.License | Should -Be "SSPL"
            $result.LicenseUrl | Should -Be "https://www.mongodb.com/licensing/server-side-public-license"
            $result.PrivacyUrl | Should -Be "https://www.mongodb.com/legal/privacy-policy"
            $result.Copyright | Should -Be "Copyright (c) MongoDB, Inc."
            $result.CopyrightUrl | Should -Be "https://www.mongodb.com/legal/copyright"
            $result.Tags | Should -Be "mongodb", "shell", "cli"
            $result.Installer | Should -Be "wix"
        }

        It "Parses GitHub Publisher URL correctly" {
             $result = InModuleScope WingetBatch {
                 $output = @"
Publisher Url: https://github.com/microsoft/winget-cli
"@
                Parse-WingetShowOutput -Output $output -PackageId "Test"
             }

             $result.PublisherGitHub | Should -Be "https://github.com/microsoft/winget-cli"
        }
    }

    Context "Edge Cases" {
        It "Handles extra whitespace around keys and values" {
             $result = InModuleScope WingetBatch {
                 $output = @"
  Version:   1.0.0
   Publisher:    Test Pub
"@
                Parse-WingetShowOutput -Output $output -PackageId "Test"
             }

             $result.Version | Should -Be "1.0.0"
             $result.Publisher | Should -Be "Test Pub"
        }

        It "Handles empty values gracefully" {
             $result = InModuleScope WingetBatch {
                 $output = @"
Version:
Publisher:
"@
                Parse-WingetShowOutput -Output $output -PackageId "Test"
             }

             $result.Version | Should -BeNullOrEmpty
             $result.Publisher | Should -BeNullOrEmpty
        }

        It "Handles lines without colons (ignores them)" {
             $result = InModuleScope WingetBatch {
                 $output = @"
Just some text
Another line
"@
                Parse-WingetShowOutput -Output $output -PackageId "Test"
             }

             $result.Version | Should -BeNull
        }

        It "Handles keys with spaces correctly" {
             $result = InModuleScope WingetBatch {
                 $output = @"
Release Notes Url: https://example.com/notes
"@
                Parse-WingetShowOutput -Output $output -PackageId "Test"
             }

             $result.ReleaseNotesUrl | Should -Be "https://example.com/notes"
        }

        It "Handles colons in values correctly" {
             $result = InModuleScope WingetBatch {
                 $output = @"
Description: This is a description: with a colon
"@
                Parse-WingetShowOutput -Output $output -PackageId "Test"
             }

             $result.Description | Should -Be "This is a description: with a colon"
        }
    }

    Context "Input Types" {
        It "Parses array of strings correctly" {
             $result = InModuleScope WingetBatch {
                 $output = @(
                    "Version: 1.0.0",
                    "Publisher: Array Test"
                 )
                Parse-WingetShowOutput -Output $output -PackageId "Test"
             }

             $result.Version | Should -Be "1.0.0"
             $result.Publisher | Should -Be "Array Test"
        }

        It "Parses ErrorRecord objects in array gracefully" {
             $result = InModuleScope WingetBatch {
                 # Mock an ErrorRecord
                 $err = [System.Management.Automation.ErrorRecord]::new(
                    [Exception]::new("Test Error"),
                    "TestErrorId",
                    [System.Management.Automation.ErrorCategory]::NotSpecified,
                    $null
                 )

                 $output = @(
                    "Version: 2.0.0",
                    $err
                 )
                Parse-WingetShowOutput -Output $output -PackageId "Test"
             }

             $result.Version | Should -Be "2.0.0"
        }
    }
}
