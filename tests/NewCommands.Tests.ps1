BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot ".." "WingetBatch.psd1"
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe "Get-WingetMachineState" {
    BeforeEach {
        # Mock the COM API module check
        Mock Get-Module { $true } -ParameterFilter { $Name -eq 'Microsoft.WinGet.Client' }
        Mock Import-Module {} -ParameterFilter { $Name -eq 'PwshSpectreConsole' }
    }

    Context "Export parameter set" {
        It "Should have Export parameter" {
            $cmd = Get-Command Get-WingetMachineState
            $cmd.Parameters.ContainsKey('Export') | Should -Be $true
        }

        It "Should have Path parameter" {
            $cmd = Get-Command Get-WingetMachineState
            $cmd.Parameters.ContainsKey('Path') | Should -Be $true
        }

        It "Should have Format parameter with JSON and YAML options" {
            $cmd = Get-Command Get-WingetMachineState
            $formatParam = $cmd.Parameters['Format']
            $formatParam | Should -Not -BeNullOrEmpty
        }

        It "Should have IncludeVersions switch" {
            $cmd = Get-Command Get-WingetMachineState
            $cmd.Parameters.ContainsKey('IncludeVersions') | Should -Be $true
        }
    }

    Context "Compare parameter set" {
        It "Should have Compare parameter" {
            $cmd = Get-Command Get-WingetMachineState
            $cmd.Parameters.ContainsKey('Compare') | Should -Be $true
        }

        It "Should error when manifest file does not exist" {
            Mock Test-Path { $false }
            { Get-WingetMachineState -Compare -Path "C:\nonexistent\state.json" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Reconcile parameter set" {
        It "Should have Reconcile parameter" {
            $cmd = Get-Command Get-WingetMachineState
            $cmd.Parameters.ContainsKey('Reconcile') | Should -Be $true
        }

        It "Should have RemoveExtraneous switch" {
            $cmd = Get-Command Get-WingetMachineState
            $cmd.Parameters.ContainsKey('RemoveExtraneous') | Should -Be $true
        }
    }

    Context "Parameter validation" {
        It "Should require Path for Export" {
            $cmd = Get-Command Get-WingetMachineState
            $pathParam = $cmd.Parameters['Path']
            $pathParam.ParameterSets.Values | Where-Object { $_.IsMandatory } | Should -Not -BeNullOrEmpty
        }

        It "Should have Source parameter for filtering" {
            $cmd = Get-Command Get-WingetMachineState
            $cmd.Parameters.ContainsKey('Source') | Should -Be $true
        }
    }
}

Describe "Get-WingetPackageInfo" {
    Context "Parameter sets" {
        It "Should have ById parameter set" {
            $cmd = Get-Command Get-WingetPackageInfo
            $cmd.ParameterSets.Name | Should -Contain 'ById'
        }

        It "Should have ByQuery parameter set" {
            $cmd = Get-Command Get-WingetPackageInfo
            $cmd.ParameterSets.Name | Should -Contain 'ByQuery'
        }

        It "Should have ShowManifest switch" {
            $cmd = Get-Command Get-WingetPackageInfo
            $cmd.Parameters.ContainsKey('ShowManifest') | Should -Be $true
        }

        It "Should have ShowVersions switch" {
            $cmd = Get-Command Get-WingetPackageInfo
            $cmd.Parameters.ContainsKey('ShowVersions') | Should -Be $true
        }
    }

    Context "ById parameter" {
        It "Should accept Id as positional parameter" {
            $cmd = Get-Command Get-WingetPackageInfo
            $idParam = $cmd.Parameters['Id']
            $paramAttr = $idParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Position -ge 0 }
            $paramAttr | Should -Not -BeNullOrEmpty
        }

        It "Should validate Id is not null or empty" {
            $cmd = Get-Command Get-WingetPackageInfo
            $idParam = $cmd.Parameters['Id']
            $idParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] } | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Find-WingetDuplicate" {
    Context "Parameters" {
        It "Should have IncludeVersions switch" {
            $cmd = Get-Command Find-WingetDuplicate
            $cmd.Parameters.ContainsKey('IncludeVersions') | Should -Be $true
        }

        It "Should have ExportHtml switch" {
            $cmd = Get-Command Find-WingetDuplicate
            $cmd.Parameters.ContainsKey('ExportHtml') | Should -Be $true
        }
    }

    Context "Function availability" {
        It "Should be exported from the module" {
            Get-Command Find-WingetDuplicate -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-WingetHistory" {
    Context "Parameters" {
        It "Should have Days parameter with default 30" {
            $cmd = Get-Command Get-WingetHistory
            $daysParam = $cmd.Parameters['Days']
            $daysParam | Should -Not -BeNullOrEmpty
        }

        It "Should have All switch" {
            $cmd = Get-Command Get-WingetHistory
            $cmd.Parameters.ContainsKey('All') | Should -Be $true
        }

        It "Should have Search parameter" {
            $cmd = Get-Command Get-WingetHistory
            $cmd.Parameters.ContainsKey('Search') | Should -Be $true
        }

        It "Should have ExportHtml switch" {
            $cmd = Get-Command Get-WingetHistory
            $cmd.Parameters.ContainsKey('ExportHtml') | Should -Be $true
        }

        It "Should have ExportJson switch" {
            $cmd = Get-Command Get-WingetHistory
            $cmd.Parameters.ContainsKey('ExportJson') | Should -Be $true
        }

        It "Should validate Days range 1-3650" {
            $cmd = Get-Command Get-WingetHistory
            $daysParam = $cmd.Parameters['Days']
            $rangeAttr = $daysParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $rangeAttr | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Watch-WingetPackages" {
    Context "Parameters" {
        It "Should have RefreshInterval parameter" {
            $cmd = Get-Command Watch-WingetPackages
            $cmd.Parameters.ContainsKey('RefreshInterval') | Should -Be $true
        }

        It "Should have Once switch" {
            $cmd = Get-Command Watch-WingetPackages
            $cmd.Parameters.ContainsKey('Once') | Should -Be $true
        }

        It "Should validate RefreshInterval range 5-3600" {
            $cmd = Get-Command Watch-WingetPackages
            $param = $cmd.Parameters['RefreshInterval']
            $rangeAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $rangeAttr | Should -Not -BeNullOrEmpty
        }
    }
}
