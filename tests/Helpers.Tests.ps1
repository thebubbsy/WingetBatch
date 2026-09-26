BeforeAll {
    $modulePath = Join-Path $PSScriptRoot ".." "WingetBatch.psd1"
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe "Compare-WingetVersion" {
    It "compares <A> vs <B> as <Expected>" -TestCases @(
        @{ A = '10.0'; B = '9.0'; Expected = 1 }
        @{ A = '2.9'; B = '2.10'; Expected = -1 }
        @{ A = '1.2.3'; B = '1.2.3.0'; Expected = 0 }
        @{ A = '1.0'; B = '1.0-beta'; Expected = 1 }
        @{ A = '1.0-beta2'; B = '1.0-beta10'; Expected = -1 }
        @{ A = 'v2.1'; B = '2.1'; Expected = 0 }
        @{ A = '2024.01.15'; B = '2023.12.31'; Expected = 1 }
        @{ A = '1.2.3.4.5'; B = '1.2.3.4.6'; Expected = -1 }
        @{ A = ''; B = '1.0'; Expected = -1 }
    ) {
        InModuleScope WingetBatch -Parameters @{ A = $A; B = $B; Expected = $Expected } {
            Compare-WingetVersion -ReferenceVersion $A -DifferenceVersion $B | Should -Be $Expected
        }
    }
}

Describe "Sort-WingetVersion" {
    It "sorts versions numerically, newest first" {
        InModuleScope WingetBatch {
            $sorted = Sort-WingetVersion -InputObject @('9.0', '10.0', '1.5', '10.0-rc1', '2.0') -Descending
            $sorted | Should -Be @('10.0', '10.0-rc1', '9.0', '2.0', '1.5')
        }
    }

    It "sorts objects by a property and returns a flat array" {
        InModuleScope WingetBatch {
            $objs = @([PSCustomObject]@{ Name = '1.9' }, [PSCustomObject]@{ Name = '1.10' })
            $sorted = @(Sort-WingetVersion -InputObject $objs -Property Name -Descending)
            $sorted.Count | Should -Be 2
            $sorted[0].Name | Should -Be '1.10'
        }
    }
}

Describe "ConvertTo-WingetActionResult" {
    It "treats Status Ok as success and carries RebootRequired" {
        InModuleScope WingetBatch {
            $r = ConvertTo-WingetActionResult -Result ([PSCustomObject]@{ Status = 'Ok'; RebootRequired = $true }) -Id 'A.B' -Action Install
            $r.Succeeded | Should -BeTrue
            $r.RebootRequired | Should -BeTrue
        }
    }

    It "reports an installer failure even though no exception was thrown" {
        InModuleScope WingetBatch {
            $r = ConvertTo-WingetActionResult -Result ([PSCustomObject]@{ Status = 'InstallError'; InstallerErrorCode = 1603 }) -Id 'A.B' -Action Install
            $r.Succeeded | Should -BeFalse
            $r.Message | Should -Match 'InstallError'
            $r.Message | Should -Match '1603'
        }
    }

    It "treats NoApplicableUpgrade as success for updates only" {
        InModuleScope WingetBatch {
            $res = [PSCustomObject]@{ Status = 'NoApplicableUpgrade' }
            (ConvertTo-WingetActionResult -Result $res -Id 'A.B' -Action Update).Succeeded | Should -BeTrue
            (ConvertTo-WingetActionResult -Result $res -Id 'A.B' -Action Install).Succeeded | Should -BeFalse
        }
    }

    It "fails when WinGet returns nothing" {
        InModuleScope WingetBatch {
            (ConvertTo-WingetActionResult -Result $null -Id 'A.B' -Action Uninstall).Succeeded | Should -BeFalse
        }
    }
}

Describe "Invoke-WingetPackageAction" {
    BeforeAll {
        # Stand-in for Microsoft.WinGet.Client\Install-WinGetPackage with the same core parameters
        function global:Test-FakeInstall {
            [CmdletBinding()]
            param($Id, $MatchOption, $Version, $Source, $Mode, [switch]$Force, $Scope)
            $global:FakeInstallArgs = $PSBoundParameters
            [PSCustomObject]@{ Status = $global:FakeInstallStatus; RebootRequired = $false }
        }
    }
    AfterAll {
        Remove-Item function:global:Test-FakeInstall -ErrorAction SilentlyContinue
    }

    It "matches the ID exactly and passes only supported, non-empty options" {
        $global:FakeInstallStatus = 'Ok'
        InModuleScope WingetBatch {
            Mock Get-Command { Get-Command Test-FakeInstall } -ParameterFilter { $Name -like 'Microsoft.WinGet.Client\*' }
            $r = Invoke-WingetPackageAction -Action Install -Id 'Git.Git' -Version 'latest' -Source 'winget' `
                -Options @{ Mode = 'Silent'; Scope = $null; Force = $false; Override = '--foo' }
            $r.Succeeded | Should -BeTrue
        }
        $global:FakeInstallArgs['MatchOption'] | Should -Be 'EqualsCaseInsensitive'
        $global:FakeInstallArgs['Source'] | Should -Be 'winget'
        $global:FakeInstallArgs['Mode'] | Should -Be 'Silent'
        $global:FakeInstallArgs.ContainsKey('Version') | Should -BeFalse   # 'latest' is not a real version
        $global:FakeInstallArgs.ContainsKey('Scope') | Should -BeFalse     # empty values are dropped
        $global:FakeInstallArgs.ContainsKey('Force') | Should -BeFalse     # false switches are dropped
        $global:FakeInstallArgs.ContainsKey('Override') | Should -BeFalse  # unsupported by this cmdlet
    }

    It "returns a failure result when the installer fails" {
        $global:FakeInstallStatus = 'InstallError'
        InModuleScope WingetBatch {
            Mock Get-Command { Get-Command Test-FakeInstall } -ParameterFilter { $Name -like 'Microsoft.WinGet.Client\*' }
            (Invoke-WingetPackageAction -Action Install -Id 'Git.Git').Succeeded | Should -BeFalse
        }
    }
}

Describe "Get-WingetYamlValue" {
    It "reads plain, quoted and block values" {
        InModuleScope WingetBatch {
            $yaml = @"
PackageIdentifier: Git.Git
License: 'GPL-2.0'
ShortDescription: "A VCS"
ReleaseNotes: |-
  Line one
  Line two
Tags:
- git
"@
            Get-WingetYamlValue -Yaml $yaml -Key 'PackageIdentifier' | Should -Be 'Git.Git'
            Get-WingetYamlValue -Yaml $yaml -Key 'License' | Should -Be 'GPL-2.0'
            Get-WingetYamlValue -Yaml $yaml -Key 'ShortDescription' | Should -Be 'A VCS'
            Get-WingetYamlValue -Yaml $yaml -Key 'ReleaseNotes' | Should -Be "Line one`nLine two"
            Get-WingetYamlValue -Yaml $yaml -Key 'Missing' | Should -BeNullOrEmpty
        }
    }
}

Describe "Parse-WingetShowOutput multi-line fields" {
    It "reads Description, Tags and Release Notes written on the lines below their label" {
        InModuleScope WingetBatch {
            $out = @"
Found Git [Git.Git]
Version: 2.55.0.3
Description:
  Git is a free VCS.
  It is fast.
Tags:
  git
  vcs
Release Notes:
  - Fixes: a crash
Installer:
  Installer Type: inno
"@
            $i = Parse-WingetShowOutput -Output $out -PackageId 'Git.Git'
            $i.Description | Should -Be 'Git is a free VCS. It is fast.'
            $i.Tags | Should -Be @('git', 'vcs')
            $i.ReleaseNotes | Should -Be '- Fixes: a crash'
            $i.Installer | Should -Be 'inno'
            $i.Version | Should -Be '2.55.0.3'
        }
    }
}

Describe "Get-WingetPkgsPackagePath" {
    It "maps IDs to winget-pkgs folders" {
        InModuleScope WingetBatch {
            Get-WingetPkgsPackagePath -PackageId 'Python.Python.3.13' | Should -Be 'manifests/p/Python/Python/3/13'
        }
    }
}

Describe "Config read-modify-write" {
    It "keeps existing keys when another setting is saved" {
        InModuleScope WingetBatch {
            Mock Get-WingetBatchConfigDir { Join-Path $TestDrive 'cfg' }
            $c = Get-WingetBatchConfigData
            $c['webhook_discord'] = 'https://example.invalid/hook'
            Save-WingetBatchConfigData -Config $c

            Set-WingetBatchConfig -SearchMatchOption EqualsCaseInsensitive 6>$null
            Send-WingetWebhook -Platform Slack -SaveConfig -WebhookUrl 'https://example.invalid/slack' 6>$null

            $after = Get-WingetBatchConfigData
            $after['webhook_discord'] | Should -Be 'https://example.invalid/hook'
            $after['webhook_slack'] | Should -Be 'https://example.invalid/slack'
            $after['SearchMatchOption'] | Should -Be 'EqualsCaseInsensitive'
        }
    }
}

Describe "Command contracts" {
    It "Send-WingetWebhook -SaveConfig does not require -Event" {
        InModuleScope WingetBatch {
            Mock Get-WingetBatchConfigData { @{} }
            Mock Save-WingetBatchConfigData { }
            Mock Invoke-RestMethod { }
            Send-WingetWebhook -Platform Discord -SaveConfig -WebhookUrl 'https://example.invalid/x' 6>$null
            Should -Invoke Save-WingetBatchConfigData -Times 1
            Should -Invoke Invoke-RestMethod -Times 0
        }
    }

    It "Test-WingetCompliance -NewPolicy accepts -PolicyPath" {
        $set = (Get-Command Test-WingetCompliance).ParameterSets | Where-Object Name -eq 'Generate'
        $set.Parameters.Name | Should -Contain 'PolicyPath'
    }

    It "Get-WingetMachineState reports a missing manifest instead of failing to find its helpers" {
        { Get-WingetMachineState -Compare -Path (Join-Path $TestDrive 'nope.json') -ErrorAction Stop } |
            Should -Throw '*State manifest not found*'
    }

    It "Get-WingetUpdates exposes -ListOnly for scripts" {
        (Get-Command Get-WingetUpdates).Parameters.ContainsKey('ListOnly') | Should -BeTrue
    }
}

Describe "Source hygiene" {
    BeforeAll {
        $root = Join-Path $PSScriptRoot ".."
        $script:files = Get-ChildItem (Join-Path $root 'Public'), (Join-Path $root 'Private') -Filter *.ps1
    }

    It "every source file parses" {
        foreach ($f in $files) {
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty -Because $f.Name
        }
    }

    It "defines each function once per file, and only functions at top level" {
        # A bad edit once left an old copy of a function after the new one; PowerShell
        # silently keeps the last definition, so the fix never ran.
        foreach ($f in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $top = @($ast.EndBlock.Statements)
            $functions = @($top | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
            ($top.Count - $functions.Count) | Should -Be 0 -Because "$($f.Name) should only define functions"
            @($functions.Name | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty -Because $f.Name
            if ($f.Directory.Name -eq 'Public') { $functions.Name | Should -Contain $f.BaseName }
        }
    }

    It "never uses Get-Date -ToString (not a real parameter)" {
        $hits = $files | Select-String -Pattern 'Get-Date -ToString'
        $hits | Should -BeNullOrEmpty
    }

    It "calls WinGet cmdlets by module-qualified name (other modules shadow them)" {
        # Inspect actual command invocations in the syntax tree, not help text or strings
        $hits = foreach ($f in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                Where-Object { $_.GetCommandName() -match '^(Get|Find|Install|Update|Uninstall|Export)-WinGet(Package|Version)$' } |
                ForEach-Object { "$($f.Name):$($_.Extent.StartLineNumber)" }
        }
        $hits | Should -BeNullOrEmpty
    }

    It "keeps release notes under the PowerShell Gallery's 10,600 character limit" {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot ".." "WingetBatch.psd1")
        $manifest.PrivateData.PSData.ReleaseNotes.Length | Should -BeLessOrEqual 10600
    }

    It "declares the PowerShell version its dependencies actually need" {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot ".." "WingetBatch.psd1")
        [version]$manifest.PowerShellVersion | Should -BeGreaterOrEqual ([version]'7.4')
    }
}
