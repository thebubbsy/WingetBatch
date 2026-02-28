Describe "Get-WingetBatchConfigDir" {
    BeforeAll {
        # Dot-source the module to access internal functions
        . "$PSScriptRoot/../WingetBatch.psm1"
    }

    It "Returns the expected configuration directory path" {
        $basePath = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        $expectedPath = Join-Path -Path $basePath -ChildPath ".wingetbatch"
        $actualPath = Get-WingetBatchConfigDir
        $actualPath | Should -Be $expectedPath
    }
}
