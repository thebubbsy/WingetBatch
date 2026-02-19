Describe "Get-WingetBatchConfigDir" {
    BeforeAll {
        # Dot-source the module to access internal functions
        . "$PSScriptRoot/../WingetBatch.psm1"
    }

    It "Returns the expected configuration directory path" {
        $expectedPath = Join-Path $env:USERPROFILE ".wingetbatch"
        $actualPath = Get-WingetBatchConfigDir
        $actualPath | Should -Be $expectedPath
    }
}
