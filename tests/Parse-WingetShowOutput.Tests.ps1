
BeforeAll {
    # Import the module so we can use InModuleScope
    Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force
}

Describe "Parse-WingetShowOutput" {
    Context "Parsing Standard Output" {
        BeforeAll {
            $sampleOutput = @"
Found Python [Python.Python.3.11]
Version: 3.11.5
Publisher: Python Software Foundation
Publisher Url: https://www.python.org/
Author: Python Software Foundation
Homepage: https://www.python.org/
Description: Python is a programming language that lets you work quickly and integrate systems more effectively.
Category: Developer Tools
Tags: python, programming, language, scripting
License: Python Software Foundation License
License Url: https://docs.python.org/3/license.html
Copyright: Copyright (c) 2001-2023 Python Software Foundation. All rights reserved.
Copyright Url: https://www.python.org/psf/
Privacy Url: https://www.python.org/privacy/
Package Url: https://www.python.org/downloads/
Release Notes: https://docs.python.org/release/3.11.5/
Release Notes Url: https://docs.python.org/release/3.11.5/
Installer Type: exe
Pricing: Free
Store License: Free
Free Trial: No
Age Rating: 3+
Moniker: python
"@
            # We need to invoke the internal function inside the module scope
            $result = InModuleScope WingetBatch {
                Parse-WingetShowOutput -Output $args[0] -PackageId "Python.Python.3.11"
            } -ArgumentList $sampleOutput
        }

        It "Parses Version correctly" {
            $result.Version | Should -Be "3.11.5"
        }

        It "Parses Publisher correctly" {
            $result.Publisher | Should -Be "Python Software Foundation"
        }

        It "Parses Publisher Url correctly" {
            $result.PublisherUrl | Should -Be "https://www.python.org/"
        }

        It "Parses Description correctly" {
            $result.Description | Should -Be "Python is a programming language that lets you work quickly and integrate systems more effectively."
        }

        It "Parses Tags correctly as an array" {
            $result.Tags -is [System.Array] | Should -Be $true
            $result.Tags.Count | Should -Be 4
            $result.Tags[0] | Should -Be "python"
        }

        It "Parses Moniker correctly" {
            $result.Moniker | Should -Be "python"
        }
    }

    Context "Edge Cases" {
        It "Handles missing fields gracefully" {
            $output = "Version: 1.0.0"
            $result = InModuleScope WingetBatch {
                Parse-WingetShowOutput -Output $args[0] -PackageId "Test.Package"
            } -ArgumentList $output

            $result.Version | Should -Be "1.0.0"
            $result.Publisher | Should -BeNullOrEmpty
        }

        It "Handles extra whitespace" {
            $output = "   Version:    2.0.0   "
            $result = InModuleScope WingetBatch {
                Parse-WingetShowOutput -Output $args[0] -PackageId "Test.Package"
            } -ArgumentList $output

            $result.Version | Should -Be "2.0.0"
        }

        It "Handles empty output" {
            $output = ""
            $result = InModuleScope WingetBatch {
                Parse-WingetShowOutput -Output $args[0] -PackageId "Test.Package"
            } -ArgumentList $output

            $result.Id | Should -Be "Test.Package"
        }
    }
}
