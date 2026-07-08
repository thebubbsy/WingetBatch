Describe "Get-WingetBatchConfigDir" {
    BeforeAll {
        # Get-WingetBatchConfigDir is an internal (non-exported) function, so we
        # import the module and reach into its scope with InModuleScope.
        # NOTE: You cannot dot-source a .psm1 directly -- PowerShell only treats
        # .ps1 as a runnable/dot-sourceable script, so `. ./WingetBatch.psm1`
        # throws "Application not found". Always Import-Module + InModuleScope.
        Import-Module "$PSScriptRoot/../WingetBatch.psd1" -Force
    }

    It "Returns the expected configuration directory path" {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        $expectedPath = Join-Path $homeDir ".wingetbatch"
        $actualPath = InModuleScope WingetBatch { Get-WingetBatchConfigDir }
        $actualPath | Should -Be $expectedPath
    }
}
