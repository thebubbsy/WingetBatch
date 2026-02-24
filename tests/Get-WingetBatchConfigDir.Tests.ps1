Describe "Get-WingetBatchConfigDir" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force
    }

    It "Returns the expected configuration directory path" {
        $base = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        $expectedPath = Join-Path $base ".wingetbatch"
        $actualPath = InModuleScope WingetBatch { Get-WingetBatchConfigDir }
        $actualPath | Should -Be $expectedPath
    }
}
