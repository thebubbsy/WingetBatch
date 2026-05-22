Describe "Parse-WingetShowOutput" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../WingetBatch.psd1" -Force
    }

    Context "Standard Output Parsing" {
        It "Parses standard fields correctly" {
            $result = InModuleScope WingetBatch {
                $testOut = "Found MongoDB Shell [MongoDB.Shell]`r`nVersion: 2.3.2`r`nPublisher: MongoDB, Inc.`r`nPublisher Url: https://www.mongodb.com/`r`nAuthor: MongoDB, Inc.`r`nMoniker: mongosh`r`nDescription: The MongoDB Shell description.`r`nHomepage: https://www.mongodb.com/try/download/shell`r`nLicense: SSPL`r`nLicense Url: https://www.mongodb.com/licensing/server-side-public-license`r`nPrivacy Url: https://www.mongodb.com/legal/privacy-policy`r`nCopyright: Copyright (c) MongoDB, Inc.`r`nCopyright Url: https://www.mongodb.com/legal/copyright`r`nTags: mongodb, shell, cli`r`nInstaller:`r`n  Installer Type: wix`r`n"
                Parse-WingetShowOutput -Output $testOut -PackageId "MongoDB.Shell"
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
                $testOut = "Publisher Url: https://github.com/microsoft/winget-cli`r`n"
                Parse-WingetShowOutput -Output $testOut -PackageId "Test"
             }

             $result.PublisherGitHub | Should -Be "https://github.com/microsoft/winget-cli"
        }
    }

    Context "Edge Cases" {
        It "Handles extra whitespace around keys and values" {
             $result = InModuleScope WingetBatch {
                $testOut = "  Version:   1.0.0`r`n   Publisher:    Test Pub`r`n"
                Parse-WingetShowOutput -Output $testOut -PackageId "Test"
             }

             $result.Version | Should -Be "1.0.0"
             $result.Publisher | Should -Be "Test Pub"
        }

        It "Handles empty values gracefully" {
             $result = InModuleScope WingetBatch {
                $testOut = "Version:`r`nPublisher:`r`n"
                Parse-WingetShowOutput -Output $testOut -PackageId "Test"
             }

             $result.Version | Should -BeNullOrEmpty
             $result.Publisher | Should -BeNullOrEmpty
        }

        It "Handles lines without colons (ignores them)" {
             $result = InModuleScope WingetBatch {
                $testOut = "Just some text`r`nAnother line`r`n"
                Parse-WingetShowOutput -Output $testOut -PackageId "Test"
             }

             $result.Version | Should -BeNull
        }

        It "Handles keys with spaces correctly" {
             $result = InModuleScope WingetBatch {
                $testOut = "Release Notes Url: https://example.com/notes`r`n"
                Parse-WingetShowOutput -Output $testOut -PackageId "Test"
             }

             $result.ReleaseNotesUrl | Should -Be "https://example.com/notes"
        }

        It "Handles colons in values correctly" {
             $result = InModuleScope WingetBatch {
                $testOut = "Description: This is a description: with a colon`r`n"
                Parse-WingetShowOutput -Output $testOut -PackageId "Test"
             }

             $result.Description | Should -Be "This is a description: with a colon"
        }
    }
}
