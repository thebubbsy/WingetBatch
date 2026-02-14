
Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force

InModuleScope WingetBatch {
    Describe "Parse-WingetShowOutput" {
        Context "Parsing Standard Output" {
            BeforeAll {
                $output = @'
Found Spotify [Spotify.Spotify]
Version: 1.2.26.1187.g36b715a1
Publisher: Spotify AB
Publisher Url: https://www.spotify.com/
Author: Spotify AB
Moniker: spotify
Description: Spotify is a digital music service.
Homepage: https://www.spotify.com/
License: Proprietary
License Url: https://www.spotify.com/legal/end-user-agreement/
Privacy Url: https://www.spotify.com/legal/privacy-policy/
Copyright: Copyright © 2024 Spotify AB
Copyright Url: https://www.spotify.com/legal/copyright-policy/
Tags: music, player, audio
Installer Type: exe
Pricing: Free
Store License: terms
Free Trial: No
Age Rating: 12+
'@
            }

            It "Parses basic fields correctly" {
                $result = Parse-WingetShowOutput -Output $output -PackageId "Spotify.Spotify"

                $result.Id | Should -Be "Spotify.Spotify"
                $result.Version | Should -Be "1.2.26.1187.g36b715a1"
                $result.PublisherName | Should -Be "Spotify AB"
                $result.Publisher | Should -Be "Spotify AB"
                $result.Moniker | Should -Be "spotify"
                $result.Description | Should -Be "Spotify is a digital music service."
                $result.License | Should -Be "Proprietary"
                $result.Copyright | Should -Be "Copyright © 2024 Spotify AB"
                $result.Pricing | Should -Be "Free"
                $result.StoreLicense | Should -Be "terms"
                $result.FreeTrial | Should -Be "No"
                $result.AgeRating | Should -Be "12+"
            }

            It "Parses URLs correctly" {
                $result = Parse-WingetShowOutput -Output $output -PackageId "Spotify.Spotify"

                $result.PublisherUrl | Should -Be "https://www.spotify.com/"
                $result.Homepage | Should -Be "https://www.spotify.com/"
                $result.LicenseUrl | Should -Be "https://www.spotify.com/legal/end-user-agreement/"
                $result.PrivacyUrl | Should -Be "https://www.spotify.com/legal/privacy-policy/"
                $result.CopyrightUrl | Should -Be "https://www.spotify.com/legal/copyright-policy/"
            }

            It "Parses Tags correctly (comma separated)" {
                $result = Parse-WingetShowOutput -Output $output -PackageId "Spotify.Spotify"

                $result.Tags | Should -Contain "music"
                $result.Tags | Should -Contain "player"
                $result.Tags | Should -Contain "audio"
                $result.Tags.Count | Should -Be 3
            }

            It "Parses Installer Type" {
                $result = Parse-WingetShowOutput -Output $output -PackageId "Spotify.Spotify"
                $result.Installer | Should -Be "exe"
            }
        }

        Context "Publisher GitHub URL" {
            It "Detects GitHub URL in Publisher Url" {
                $outputWithGithub = @'
Publisher Url: https://github.com/microsoft/winget-cli
'@
                $result = Parse-WingetShowOutput -Output $outputWithGithub -PackageId "Test"
                $result.PublisherGitHub | Should -Be "https://github.com/microsoft/winget-cli"
            }

            It "Does not detect non-GitHub URL" {
                $outputNoGithub = @'
Publisher Url: https://microsoft.com
'@
                $result = Parse-WingetShowOutput -Output $outputNoGithub -PackageId "Test"
                $result.PublisherGitHub | Should -BeNullOrEmpty
            }
        }

        Context "Edge Cases" {
            It "Handles empty output" {
                $result = Parse-WingetShowOutput -Output "" -PackageId "Empty"
                $result.Id | Should -Be "Empty"
                $result.Version | Should -BeNullOrEmpty
            }

            It "Handles output with colons in values" {
                $outputColons = @'
Description: This description: contains a colon
'@
                $result = Parse-WingetShowOutput -Output $outputColons -PackageId "Test"
                $result.Description | Should -Be "This description: contains a colon"
            }
        }
    }
}
