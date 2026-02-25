Describe "Parse-WingetSearchOutput" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force
    }

    Context "Standard Search Output" {
        It "Parses standard output correctly" {
            $result = InModuleScope WingetBatch {
                $lines = @(
                    "Name                               Id               Version  Source",
                    "-------------------------------------------------------------------",
                    "Test Package 1                     Test.Package.1   1.0.0    winget",
                    "Test Package 2                     Test.Package.2   2.0.0    winget"
                )
                Parse-WingetSearchOutput -Lines $lines -Query "Test"
            }

            $result.Count | Should -Be 2
            $result[0].Name | Should -Be "Test Package 1"
            $result[0].Id | Should -Be "Test.Package.1"
            $result[0].Version | Should -Be "1.0.0"
            $result[0].Source | Should -Be "winget"
            $result[0].SearchTerm | Should -Be "Test"

            $result[1].Id | Should -Be "Test.Package.2"
        }

        It "Parses output with Match column correctly" {
            $result = InModuleScope WingetBatch {
                $lines = @(
                    "Name           Id             Version  Match       Source",
                    "---------------------------------------------------------",
                    "Test Pkg       Test.Id        1.2.3    Tag: test   winget"
                )
                Parse-WingetSearchOutput -Lines $lines -Query "Test"
            }

            $result.Count | Should -Be 1
            $result[0].Id | Should -Be "Test.Id"
            $result[0].Version | Should -Be "1.2.3"
        }
    }

    Context "Deduplication" {
        It "Deduplicates packages with same ID" {
            $result = InModuleScope WingetBatch {
                $lines = @(
                    "Name           Id             Version  Source",
                    "---------------------------------------------",
                    "Pkg 1          My.Pkg         1.0.0    winget",
                    "Pkg 1 (Dup)    My.Pkg         1.0.0    msstore"
                )
                Parse-WingetSearchOutput -Lines $lines -Query "Test"
            }

            $result.Count | Should -Be 1
            $result[0].Id | Should -Be "My.Pkg"
            $result[0].Name | Should -Be "Pkg 1"
        }
    }

    Context "Filtering" {
        It "Filters results that do not match all search terms" {
            $result = InModuleScope WingetBatch {
                $lines = @(
                    "Name           Id             Version  Source",
                    "---------------------------------------------",
                    "Visual Studio  MS.VS          1.0      winget",
                    "Visual Code    MS.Code        1.0      winget"
                )
                Parse-WingetSearchOutput -Lines $lines -Query "Visual Studio"
            }

            $result.Count | Should -Be 1
            $result[0].Id | Should -Be "MS.VS"
        }
    }

    Context "Validation" {
        It "Ignores invalid IDs" {
            $result = InModuleScope WingetBatch {
                $lines = @(
                    "Name           Id             Version  Source",
                    "---------------------------------------------",
                    "Bad ID         1.2.3          1.0      winget",  # Looks like version
                    "Bad Chars      Bad@ID         1.0      winget"   # @ not allowed
                )
                Parse-WingetSearchOutput -Lines $lines -Query "Test"
            }

            $result.Count | Should -Be 0
        }
    }

    Context "Edge Cases" {
        It "Handles empty output" {
            $result = InModuleScope WingetBatch {
                $lines = @()
                Parse-WingetSearchOutput -Lines $lines -Query "Test"
            }
            $result.Count | Should -Be 0
        }

        It "Handles output with no separator" {
            $result = InModuleScope WingetBatch {
                $lines = @(
                    "Name           Id             Version",
                    "Pkg            My.Id          1.0.0"
                )
                Parse-WingetSearchOutput -Lines $lines -Query "Test"
            }
            $result.Count | Should -Be 0
        }

        It "Handles malformed lines (too short)" {
            $result = InModuleScope WingetBatch {
                $lines = @(
                    "Name           Id             Version",
                    "-------------------------------------",
                    "Short"
                )
                Parse-WingetSearchOutput -Lines $lines -Query "Test"
            }
            $result.Count | Should -Be 0
        }
    }
}
