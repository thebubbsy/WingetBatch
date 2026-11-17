BeforeAll {
    $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "WingetBatch.psd1"
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
        $manifest = Import-PowerShellDataFile (Join-Path (Join-Path $PSScriptRoot "..") "WingetBatch.psd1")
        $manifest.PrivateData.PSData.ReleaseNotes.Length | Should -BeLessOrEqual 10600
    }

    It "supports Windows PowerShell 5.1 and PowerShell 7+ without requiring PwshSpectreConsole" {
        $manifest = Import-PowerShellDataFile (Join-Path (Join-Path $PSScriptRoot "..") "WingetBatch.psd1")
        [version]$manifest.PowerShellVersion | Should -Be ([version]'5.1')
        $manifest.CompatiblePSEditions | Should -Contain 'Desktop'
        $manifest.CompatiblePSEditions | Should -Contain 'Core'
        $manifest.RequiredModules | Should -Not -Contain 'PwshSpectreConsole'
        $manifest.RequiredModules | Should -Contain 'Microsoft.WinGet.Client'
    }

    It "ensures any file with non-ASCII characters has a UTF-8 BOM for Windows PowerShell 5.1" {
        $root = Join-Path $PSScriptRoot ".."
        $allScripts = @(Get-ChildItem (Join-Path $root 'Public'), (Join-Path $root 'Private') -Filter *.ps1) +
            @(Get-Item (Join-Path $root 'WingetBatch.psm1'), (Join-Path $root 'WingetBatch.psd1'))
        foreach ($f in $allScripts) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            $hasNonAscii = $false
            foreach ($b in $bytes) { if ($b -gt 0x7F) { $hasNonAscii = $true; break } }
            if ($hasNonAscii) {
                $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
                $hasBom | Should -BeTrue -Because "$($f.Name) contains non-ASCII characters and needs a UTF-8 BOM for PS 5.1"
            }
        }
    }
}

Describe "Start-PackageDetailJobs deadlock & batch regression" {
    It "completes background detail jobs without deadlocking and handles multi-package batches" {
        InModuleScope WingetBatch {
            $cacheDir = Join-Path $TestDrive 'wb_cache'
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            $now = (Get-Date).ToString('o')
            $cacheObj = @{
                'Pkg.One' = @{ CachedDate = $now; Details = @{ Id = 'Pkg.One'; Version = '1.0.0'; Description = 'First pkg' } }
                'Pkg.Two' = @{ CachedDate = $now; Details = @{ Id = 'Pkg.Two'; Version = '2.0.0'; Description = 'Second pkg' } }
            }
            [System.IO.File]::WriteAllText((Join-Path $cacheDir 'package_cache.json'), ($cacheObj | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

            $res = Start-PackageDetailJobs -PackageIds @('Pkg.One', 'Pkg.Two') -ConfigDir $cacheDir
            $jobs = $res[0]
            $jobs.Count | Should -BeGreaterThan 0
            $completed = $jobs | Wait-Job -Timeout 15
            @($completed).Count | Should -Be $jobs.Count

            $merged = @{}
            foreach ($j in $jobs) {
                $out = Receive-Job -Job $j
                foreach ($k in $out.Keys) { $merged[$k] = $out[$k] }
                Remove-Job -Job $j -Force
            }
            $merged['Pkg.One'].Version | Should -Be '1.0.0'
            $merged['Pkg.Two'].Version | Should -Be '2.0.0'
        }
    }

    It "executes Parse-WingetShowOutput cleanly inside a background job without module-runspace deadlock" {
        InModuleScope WingetBatch {
            $parseCode = ${function:Parse-WingetShowOutput}.ToString()
            $job = Start-WingetBatchJob -ScriptBlock {
                param($code)
                Set-Item -Path function:Parse-WingetShowOutput -Value ([scriptblock]::Create($code))
                $sample = "Found PowerShell [Microsoft.PowerShell]`nVersion: 7.7.0.0`nPublisher: Microsoft Corporation`nDescription:`n  Cross-platform shell"
                return Parse-WingetShowOutput -Output $sample -PackageId 'Microsoft.PowerShell'
            } -ArgumentList @($parseCode)
            $done = $job | Wait-Job -Timeout 15
            $done | Should -Not -BeNullOrEmpty
            $parsed = Receive-Job -Job $job
            Remove-Job -Job $job -Force
            $parsed.Version | Should -Be '7.7.0.0'
            $parsed.PublisherName | Should -Be 'Microsoft Corporation'
            $parsed.Description | Should -Be 'Cross-platform shell'
        }
    }
}

Describe "PS 5.1 compatibility helpers" {
    It "Read-WingetConsoleSelection parses single, list, range, all, and cancel" {
        InModuleScope WingetBatch {
            Mock Write-Host {}
            $choices = @('Alpha', 'Beta', 'Gamma', 'Delta')

            Mock Read-Host { '1, 3-4' }
            $idx = @(Read-WingetConsoleSelection -Title 'Pick' -Choices $choices -MultiSelect -ReturnIndex)
            $idx | Should -Be @(0, 2, 3)

            Mock Read-Host { 'all' }
            $all = @(Read-WingetConsoleSelection -Title 'Pick' -Choices $choices -MultiSelect -ReturnIndex)
            $all | Should -Be @(0, 1, 2, 3)

            Mock Read-Host { '' }
            $none = @(Read-WingetConsoleSelection -Title 'Pick' -Choices $choices -MultiSelect -ReturnIndex)
            $none.Count | Should -Be 0

            Mock Read-Host { 'y' }
            $single = @(Read-WingetConsoleSelection -Title 'Pick' -Choices @('OnlyOne') -MultiSelect -ReturnIndex)
            $single | Should -Be @(0)
        }
    }

    It "ConvertTo-WingetHashtable converts nested PSCustomObjects into hashtables" {
        InModuleScope WingetBatch {
            $ht = '{"computer":"pc1","errors":["e1"],"nested":{"k":1}}' | ConvertFrom-Json | ConvertTo-WingetHashtable
            ($ht -is [hashtable]) | Should -BeTrue
            $ht['computer'] | Should -Be 'pc1'
            $ht['errors'] | Should -Be @('e1')
            ($ht['nested'] -is [hashtable]) | Should -BeTrue
            $ht['nested']['k'] | Should -Be 1
        }
    }

    It "Set-PackageDetailsCache and Get-PackageDetailsCache handle PSCustomObject details" {
        InModuleScope WingetBatch {
            Mock Get-WingetBatchConfigDir { Join-Path $TestDrive 'cache_dir' }
            $psObj = '{"Id":"Test.Pkg","Version":"1.2.3","Description":"Hello"}' | ConvertFrom-Json
            { Set-PackageDetailsCache -PackageId 'Test.Pkg' -Details $psObj } | Should -Not -Throw
            $got = Get-PackageDetailsCache -PackageId 'Test.Pkg'
            $got | Should -Not -BeNullOrEmpty
            $got.Version | Should -Be '1.2.3'
        }
    }

    It "Import-WingetBatchSpectre does not emit a PwshSpectreConsole Warning under CP437" {
        $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "WingetBatch.psd1"
        if ($PSVersionTable.PSEdition -eq 'Core') {
            $out = pwsh -NoProfile -Command {
                param($mp)
                [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
                [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437)
                Import-Module $mp -Force
                $m = Get-Module WingetBatch
                & $m { $null = Import-WingetBatchSpectre -Force }
            } -Args $modulePath 2>&1 | Out-String
            $out | Should -Not -Match 'PwshSpectreConsole Warning'
        }
        else {
            InModuleScope WingetBatch {
                (Import-WingetBatchSpectre) | Should -BeFalse
            }
        }
    }
}
