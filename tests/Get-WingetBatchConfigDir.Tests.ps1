Describe "Get-WingetBatchConfigDir" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../WingetBatch.psd1" -Force
    }

    It "Returns the expected configuration directory path" {
        $baseDir = $HOME
        if ($env:USERPROFILE) {
            $baseDir = $env:USERPROFILE
        }
        $expectedPath = Join-Path $baseDir ".wingetbatch"

        $actualPath = InModuleScope WingetBatch {
            Get-WingetBatchConfigDir
        }
        $actualPath | Should -Be $expectedPath
    }
}
