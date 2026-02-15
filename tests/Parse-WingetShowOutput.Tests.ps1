$modulePath = "$PSScriptRoot/../WingetBatch.psm1"
Import-Module $modulePath -Force

Describe "Parse-WingetShowOutput" {
    InModuleScope "WingetBatch" {
        Context "Basic Parsing" {
            BeforeAll {
                $sampleOutput = @"
Found Microsoft Visual Studio Code [Microsoft.VSCode]
Version: 1.95.3
Publisher: Microsoft Corporation
Publisher Url: https://www.microsoft.com
Author: Microsoft Corporation
Description: Visual Studio Code is a lightweight but powerful source code editor.
Tags: electron, development, editor
License: MIT
Pricing: Free
"@
            }

            It "Parses basic fields correctly" {
                $result = Parse-WingetShowOutput -Output $sampleOutput -PackageId "Microsoft.VSCode"

                $result.Id | Should -Be "Microsoft.VSCode"
                $result.Version | Should -Be "1.95.3"
                $result.PublisherName | Should -Be "Microsoft Corporation"
                $result.PublisherUrl | Should -Be "https://www.microsoft.com"
                $result.Author | Should -Be "Microsoft Corporation"
                $result.Description | Should -Be "Visual Studio Code is a lightweight but powerful source code editor."
                $result.License | Should -Be "MIT"
                $result.Pricing | Should -Be "Free"
            }

            It "Parses tags as an array" {
                $result = Parse-WingetShowOutput -Output $sampleOutput -PackageId "Microsoft.VSCode"

                # Check if it's an array without unrolling
                $result.Tags.GetType().IsArray | Should -Be $true
                $result.Tags.Count | Should -Be 3
                $result.Tags[0] | Should -Be "electron"
                $result.Tags[1] | Should -Be "development"
                $result.Tags[2] | Should -Be "editor"
            }
        }

        Context "Complex Scenarios" {
            It "Handles fields with colons in values" {
                $output = "Description: This is a description: with a colon."
                $result = Parse-WingetShowOutput -Output $output -PackageId "Test"
                $result.Description | Should -Be "This is a description: with a colon."
            }

            It "Handles keys with spaces" {
                $output = "Store License: MS-Store"
                $result = Parse-WingetShowOutput -Output $output -PackageId "Test"
                $result.StoreLicense | Should -Be "MS-Store"
            }

            It "Handles indented lines (like Installer section)" {
                 $output = @"
Installer:
  Installer Type: inno
"@
                $result = Parse-WingetShowOutput -Output $output -PackageId "Test"
                $result.Installer | Should -Be "inno"
            }

            It "Handles empty values gracefully" {
                $output = "Homepage: "
                $result = Parse-WingetShowOutput -Output $output -PackageId "Test"
                $result.Homepage | Should -BeNullOrEmpty
            }

            It "Handles Publisher GitHub URL extraction" {
                $output = "Publisher Url: https://github.com/microsoft/vscode"
                $result = Parse-WingetShowOutput -Output $output -PackageId "Test"
                $result.PublisherGitHub | Should -Be "https://github.com/microsoft/vscode"
                $result.PublisherUrl | Should -Be "https://github.com/microsoft/vscode"
            }

            It "Handles unknown keys gracefully" {
                $output = "Unknown Key: Some Value"
                $result = Parse-WingetShowOutput -Output $output -PackageId "Test"
                $result.Keys | Should -Not -Contain "Unknown Key"
            }
        }
    }
}
