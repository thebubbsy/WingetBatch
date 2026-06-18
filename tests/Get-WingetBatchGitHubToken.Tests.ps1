Describe "Get-WingetBatchGitHubToken" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../WingetBatch.psd1" -Force
    }

    BeforeEach {
        $tempDir = New-TemporaryFile | ForEach-Object {
            Remove-Item $_
            New-Item -ItemType Directory -Path $_.FullName
        }
        $script:tempDir = $tempDir.FullName
    }

    AfterEach {
        if (Test-Path $script:tempDir) {
            Remove-Item -Path $script:tempDir -Recurse -Force
        }
    }

    Context "When no token files exist" {
        It "Returns `$null" {
            $innerTempDir = $script:tempDir
            Mock -ModuleName WingetBatch Get-WingetBatchConfigDir { return $innerTempDir }

            InModuleScope WingetBatch {
                $result = Get-WingetBatchGitHubToken
                $result | Should -BeNull
            }
        }
    }

    Context "Secure token file (clixml)" {
        It "Loads token successfully" {
            $tokenFile = Join-Path $script:tempDir "github_token.clixml"
            $secureString = ConvertTo-SecureString "secure_token" -AsPlainText -Force
            Export-Clixml -InputObject $secureString -Path $tokenFile

            $innerTempDir = $script:tempDir
            Mock -ModuleName WingetBatch Get-WingetBatchConfigDir { return $innerTempDir }

            InModuleScope WingetBatch {
                $result = Get-WingetBatchGitHubToken
                $result | Should -Be "secure_token"
            }
        }

        It "Falls back gracefully if clixml is corrupted" {
            $tokenFile = Join-Path $script:tempDir "github_token.clixml"
            Set-Content -Path $tokenFile -Value "Not a valid clixml"

            $innerTempDir = $script:tempDir
            Mock -ModuleName WingetBatch Get-WingetBatchConfigDir { return $innerTempDir }

            InModuleScope WingetBatch {
                $result = Get-WingetBatchGitHubToken
                $result | Should -BeNull
            }
        }

        It "Falls back gracefully if clixml is not a SecureString" {
            $tokenFile = Join-Path $script:tempDir "github_token.clixml"
            Export-Clixml -InputObject "Plain String" -Path $tokenFile

            $innerTempDir = $script:tempDir
            Mock -ModuleName WingetBatch Get-WingetBatchConfigDir { return $innerTempDir }

            InModuleScope WingetBatch {
                $result = Get-WingetBatchGitHubToken
                $result | Should -BeNull
            }
        }
    }

    Context "Legacy token file (plaintext)" {
        It "Migrates token and returns it when only legacy exists" {
            $legacyFile = Join-Path $script:tempDir "github_token.txt"
            Set-Content -Path $legacyFile -Value "legacy_token"

            $innerTempDir = $script:tempDir
            Mock -ModuleName WingetBatch Get-WingetBatchConfigDir { return $innerTempDir }
            Mock -ModuleName WingetBatch Set-WingetBatchGitHubToken { return $true }

            InModuleScope WingetBatch {
                $result = Get-WingetBatchGitHubToken
                $result | Should -Be "legacy_token"
            }
            Assert-MockCalled -ModuleName WingetBatch Set-WingetBatchGitHubToken -Times 1 -ParameterFilter { $Token -eq "legacy_token" }
        }

        It "Migrates token when secure file exists but is corrupted" {
            $tokenFile = Join-Path $script:tempDir "github_token.clixml"
            Set-Content -Path $tokenFile -Value "Corrupted"

            $legacyFile = Join-Path $script:tempDir "github_token.txt"
            Set-Content -Path $legacyFile -Value "legacy_token_from_corrupted"

            $innerTempDir = $script:tempDir
            Mock -ModuleName WingetBatch Get-WingetBatchConfigDir { return $innerTempDir }
            Mock -ModuleName WingetBatch Set-WingetBatchGitHubToken { return $true }

            InModuleScope WingetBatch {
                $result = Get-WingetBatchGitHubToken
                $result | Should -Be "legacy_token_from_corrupted"
            }
            Assert-MockCalled -ModuleName WingetBatch Set-WingetBatchGitHubToken -Times 1 -ParameterFilter { $Token -eq "legacy_token_from_corrupted" }
        }

        It "Ignores empty legacy token file" {
            $legacyFile = Join-Path $script:tempDir "github_token.txt"
            Set-Content -Path $legacyFile -Value "   `n   "

            $innerTempDir = $script:tempDir
            Mock -ModuleName WingetBatch Get-WingetBatchConfigDir { return $innerTempDir }
            Mock -ModuleName WingetBatch Set-WingetBatchGitHubToken { return $true }

            InModuleScope WingetBatch {
                $result = Get-WingetBatchGitHubToken
                $result | Should -BeNull
            }
            Assert-MockCalled -ModuleName WingetBatch Set-WingetBatchGitHubToken -Times 0
        }
    }
}
