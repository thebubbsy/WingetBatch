
Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force

Describe 'Parse-WingetCommitMessage' {
    InModuleScope WingetBatch {
        It 'Correctly parses "New package: <Name> version <Version>"' {
            $msg = "New package: Microsoft.PowerShell version 7.4.6"
            $result = Parse-WingetCommitMessage -Message $msg
            $result.Name | Should -Be "Microsoft.PowerShell"
            $result.Version | Should -Be "7.4.6"
        }

        It 'Correctly parses "Add: <Name> version <Version>"' {
            $msg = "Add: NodeJS version 22.0.0"
            $result = Parse-WingetCommitMessage -Message $msg
            $result.Name | Should -Be "NodeJS"
            $result.Version | Should -Be "22.0.0"
        }

        It 'Correctly parses "<Name> version <Version> (#PR)"' {
            $msg = "Something.Else version 1.2.3 (#1234)"
            $result = Parse-WingetCommitMessage -Message $msg
            $result.Name | Should -Be "Something.Else"
            $result.Version | Should -Be "1.2.3"
        }

        It 'Correctly parses "<Name> version <Version>"' {
            $msg = "Simple.Package version 1.0.0"
            $result = Parse-WingetCommitMessage -Message $msg
            $result.Name | Should -Be "Simple.Package"
            $result.Version | Should -Be "1.0.0"
        }

        It 'Returns null for Update messages' {
            $msg = "Update: Microsoft.PowerShell version 7.4.7"
            $result = Parse-WingetCommitMessage -Message $msg
            $result | Should -BeNullOrEmpty
        }

        It 'Returns null for Delete/Remove messages' {
            $msg = "Delete: Old.Package version 1.0.0"
            $result = Parse-WingetCommitMessage -Message $msg
            $result | Should -BeNullOrEmpty
        }

        It 'Returns null for messages without "version"' {
            $msg = "Merge pull request #123 from user/branch"
            $result = Parse-WingetCommitMessage -Message $msg
            $result | Should -BeNullOrEmpty
        }

        It 'Returns null for messages with "version" but not matching format' {
             $msg = "Just mentioning version 2 here"
             $result = Parse-WingetCommitMessage -Message $msg
             $result | Should -BeNullOrEmpty
        }
    }
}
