
Describe "Show-WingetPackageDetails" {
    BeforeAll {
        $sutPath = Join-Path $PSScriptRoot "../WingetBatch.psm1"
        Import-Module $sutPath -Force
    }

    AfterAll {
        Remove-Module WingetBatch -ErrorAction SilentlyContinue
    }

    Context "Output Order" {
        It "Displays Description before Version" {
            $global:CapturedOutput = @()

            InModuleScope WingetBatch {
                # Override Write-Host to capture output
                function Write-Host {
                    [CmdletBinding()]
                    param(
                        [Parameter(Position=0, ValueFromPipeline=$true)]
                        [System.Object]$Object,

                        [Parameter()]
                        [System.ConsoleColor]$ForegroundColor,

                        [Parameter()]
                        [System.ConsoleColor]$BackgroundColor,

                        [Parameter()]
                        [switch]$NoNewline,

                        [Parameter()]
                        [System.Object]$Separator
                    )

                    if ($null -ne $Object) {
                        $global:CapturedOutput += $Object
                    }
                }

                $detailsMap = @{
                    "Test.Package" = @{
                        Description = "This is the description"
                        Version = "1.0.0"
                    }
                }

                Show-WingetPackageDetails -PackageIds @("Test.Package") -DetailsMap $detailsMap
            }

            # Verify order in $global:CapturedOutput
            $descIndex = $global:CapturedOutput.IndexOf("This is the description")
            $verIndex = $global:CapturedOutput.IndexOf("1.0.0")

            # Print for debugging
            # Write-Output "Captured: $($global:CapturedOutput -join ', ')"

            $descIndex | Should -BeGreaterThan -1
            $verIndex | Should -BeGreaterThan -1

            # This assertion defines the desired UX: Description comes BEFORE Version
            $descIndex | Should -BeLessThan $verIndex
        }
    }
}
