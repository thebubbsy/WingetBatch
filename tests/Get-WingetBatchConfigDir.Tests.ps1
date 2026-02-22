Describe "Get-WingetBatchConfigDir" {
    BeforeAll {
        # Import module to test internal functions via InModuleScope
        Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force
    }

    It "Returns the expected configuration directory path" {
        $expectedPath = Join-Path $HOME ".wingetbatch"
        $actualPath = InModuleScope WingetBatch { Get-WingetBatchConfigDir }
        $actualPath | Should -Be $expectedPath
    }
}
