$modulePath = Join-Path $PSScriptRoot ".." "WingetBatch.psm1"
Import-Module $modulePath -Force

Describe "Parse-WingetShowOutput" {
    InModuleScope "WingetBatch" {
        Context "Parsing typical winget show output" {
            It "Should correctly parse all fields" {
                $output = @"
Found MongoDB Shell [MongoDB.Shell] Version 2.1.1
This package is provided through the winget source.

Version: 2.1.1
Publisher: MongoDB Inc.
Publisher Url: https://www.mongodb.com/
Author: MongoDB Inc.
Homepage: https://www.mongodb.com/try/download/shell
Description: The MongoDB Shell is the quickest way to connect to and work with MongoDB.
Category: Developer Tools
Tags: mongodb, shell, database, cli
License: Apache-2.0
License Url: https://www.mongodb.com/licensing/server-side-public-license
Copyright: Copyright (c) 2021 MongoDB Inc.
Copyright Url: https://www.mongodb.com/copyright
Privacy Url: https://www.mongodb.com/privacy
Package Url: https://github.com/mongodb-js/mongosh
Release Notes: https://github.com/mongodb-js/mongosh/releases/tag/v2.1.1
Release Notes Url: https://github.com/mongodb-js/mongosh/releases
Installer Type: wix
Pricing: Free
Store License: SomeLicense
Free Trial: No
Age Rating: 12+
Moniker: mongosh
"@
                $result = Parse-WingetShowOutput -Output $output -PackageId "MongoDB.Shell"

                $result.Id | Should -Be "MongoDB.Shell"
                $result.Version | Should -Be "2.1.1"
                $result.PublisherName | Should -Be "MongoDB Inc."
                $result.Publisher | Should -Be "MongoDB Inc."
                $result.PublisherUrl | Should -Be "https://www.mongodb.com/"
                $result.Author | Should -Be "MongoDB Inc."
                $result.Homepage | Should -Be "https://www.mongodb.com/try/download/shell"
                $result.Description | Should -Be "The MongoDB Shell is the quickest way to connect to and work with MongoDB."
                $result.Category | Should -Be "Developer Tools"

                # Verify Tags is an array and has correct content
                $result.Tags.Count | Should -Be 4
                $result.Tags[0] | Should -Be "mongodb"
                $result.Tags -join "," | Should -Be "mongodb,shell,database,cli"

                $result.License | Should -Be "Apache-2.0"
                $result.LicenseUrl | Should -Be "https://www.mongodb.com/licensing/server-side-public-license"
                $result.Copyright | Should -Be "Copyright (c) 2021 MongoDB Inc."
                $result.CopyrightUrl | Should -Be "https://www.mongodb.com/copyright"
                $result.PrivacyUrl | Should -Be "https://www.mongodb.com/privacy"
                $result.PackageUrl | Should -Be "https://github.com/mongodb-js/mongosh"
                $result.ReleaseNotes | Should -Be "https://github.com/mongodb-js/mongosh/releases/tag/v2.1.1"
                $result.ReleaseNotesUrl | Should -Be "https://github.com/mongodb-js/mongosh/releases"
                $result.Installer | Should -Be "wix"
                $result.Pricing | Should -Be "Free"
                $result.StoreLicense | Should -Be "SomeLicense"
                $result.FreeTrial | Should -Be "No"
                $result.AgeRating | Should -Be "12+"
                $result.Moniker | Should -Be "mongosh"
            }
        }

        Context "Edge cases" {
            It "Should handle empty lines and extra spaces" {
                $output = @"

Version:  1.0.0
Publisher:   Foo Bar

"@
                $result = Parse-WingetShowOutput -Output $output -PackageId "Test.Pkg"

                $result.Version | Should -Be "1.0.0"
                $result.PublisherName | Should -Be "Foo Bar"
            }

            It "Should handle missing fields" {
                 $output = @"
Version: 1.0.0
"@
                $result = Parse-WingetShowOutput -Output $output -PackageId "Test.Pkg"

                $result.Description | Should -BeNullOrEmpty
                # Tags should be empty array
                $result.Tags.Count | Should -Be 0
            }

            It "Should handle special characters in values" {
                $output = @"
Description: Works with C#, F#, & VB.NET
"@
                $result = Parse-WingetShowOutput -Output $output -PackageId "Test.Pkg"

                $result.Description | Should -Be "Works with C#, F#, & VB.NET"
            }
        }
    }
}
