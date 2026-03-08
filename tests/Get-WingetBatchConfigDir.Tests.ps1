Describe "Get-WingetBatchConfigDir" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../WingetBatch.psd1" -Force
    }

    It "Returns the expected configuration directory path" {
        InModuleScope WingetBatch {
            $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
            $expectedPath = Join-Path $homeDir ".wingetbatch"
            $actualPath = Get-WingetBatchConfigDir
            $actualPath | Should -Be $expectedPath
        }
    }
}
