Describe "Get-WingetBatchConfigDir" {
    BeforeAll {
        # Dot-source the module to access internal functions
        . "$PSScriptRoot/../WingetBatch.psm1"
    }

    It "Returns the expected configuration directory path" {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        $expectedPath = Join-Path $homeDir ".wingetbatch"
        $actualPath = Get-WingetBatchConfigDir
        $actualPath | Should -Be $expectedPath
    }
}
