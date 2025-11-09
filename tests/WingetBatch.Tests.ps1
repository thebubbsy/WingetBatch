Import-Module -Name (Join-Path $PSScriptRoot '..\WingetBatch.psm1') -Force

Describe 'ConvertFrom-WingetUpgradeOutput' {
    InModuleScope WingetBatch {
        It 'parses standard winget upgrade output into structured records' {
            $output = @'
Name                             Id                                   Version      Available    Source
------------------------------------------------------------------------------------------------------
Microsoft Edge                   Microsoft.Edge                      126.0.2592.0 126.0.2718.0 winget
Git for Windows                  Git.Git                             2.47.0       2.47.1       winget
'@

            $result = ConvertFrom-WingetUpgradeOutput -Output $output

            $result | Should -HaveCount 2
            $result[0].Id | Should -Be 'Microsoft.Edge'
            $result[0].InstalledVersion | Should -Be '126.0.2592.0'
            $result[0].AvailableVersion | Should -Be '126.0.2718.0'
            $result[0].Source | Should -Be 'winget'
        }

        It 'ignores duplicate package identifiers when parsing output' {
            $output = @'
Name                             Id                                   Version      Available    Source
------------------------------------------------------------------------------------------------------
Git for Windows                  Git.Git                             2.47.0       2.47.1       winget
Git for Windows                  Git.Git                             2.47.0       2.47.1       winget
'@

            $result = ConvertFrom-WingetUpgradeOutput -Output $output

            $result | Should -HaveCount 1
            $result[0].Id | Should -Be 'Git.Git'
        }
    }
}

Describe 'ConvertFrom-WingetUpgradeCacheRecord' {
    InModuleScope WingetBatch {
        It 'upgrades legacy cache record format with DisplayLine' {
            $legacyRecord = [pscustomobject]@{
                Id          = 'Git.Git'
                DisplayLine = 'Git for Windows            Git.Git             2.47.0      2.47.1      winget'
            }

            $result = ConvertFrom-WingetUpgradeCacheRecord -Record $legacyRecord

            $result | Should -Not -BeNullOrEmpty
            $result.Id | Should -Be 'Git.Git'
            $result.AvailableVersion | Should -Be '2.47.1'
        }
    }
}
