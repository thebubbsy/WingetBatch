Describe "Get-WingetBatchConfigDir" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force
    }

    It "Returns the expected configuration directory path" {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        $expectedPath = Join-Path $homeDir ".wingetbatch"

        $actualPath = InModuleScope WingetBatch {
            Get-WingetBatchConfigDir
        }
        $actualPath | Should -Be $expectedPath
    }
}
