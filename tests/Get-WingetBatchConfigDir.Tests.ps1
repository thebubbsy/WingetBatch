Describe "Get-WingetBatchConfigDir" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force
    }

    It "Returns the expected configuration directory path" {
        $profile = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        $expectedPath = Join-Path $profile ".wingetbatch"
        $actualPath = InModuleScope WingetBatch { Get-WingetBatchConfigDir }
        $actualPath | Should -Be $expectedPath
    }
}
