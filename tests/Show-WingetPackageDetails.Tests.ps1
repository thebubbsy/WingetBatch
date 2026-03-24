Import-Module "$PSScriptRoot/../WingetBatch.psd1" -Force

Describe "Show-WingetPackageDetails UX Improvements" {
    It "Displays Description immediately after header" {
        # Define mock data
        $pkgId = "Test.Pkg"
        $details = @{
            "Test.Pkg" = @{
                Id = "Test.Pkg"
                Description = "This is the description"
                Version = "1.0.0"
            }
        }

        # Invoke internal function using & (Get-Module) { ... } technique because InModuleScope + output redirection is tricky
        $module = Get-Module WingetBatch
        $scriptBlock = {
            param($id, $map)
            # Redirect Write-Host (stream 6) to success stream
            Show-WingetPackageDetails -PackageIds @($id) -DetailsMap $map 6>&1
        }

        $output = & $module $scriptBlock $pkgId $details
        $outputStr = $output | Out-String

        # Verify order: Header (Id) -> Description -> Version
        # Note: Write-Host output might contain newlines and formatting

        # Check if description appears before version
        $descPos = $outputStr.IndexOf("This is the description")
        $verPos = $outputStr.IndexOf("1.0.0")

        $descPos | Should -BeGreaterThan -1
        $verPos | Should -BeGreaterThan -1

        $descPos | Should -BeLessThan $verPos
    }

    It "Displays Source when available from fallback info" {
        $pkgId = "Microsoft.PowerToys"
        $details = @{
            "Microsoft.PowerToys" = @{
                Id = "Microsoft.PowerToys"
            }
        }
        $fallback = @(
            @{ Id = "Microsoft.PowerToys"; Name = "PowerToys"; Source = "winget" }
        )

        $module = Get-Module WingetBatch
        $scriptBlock = {
            param($id, $map, $fallbackInfo)
            Show-WingetPackageDetails -PackageIds @($id) -DetailsMap $map -FallbackInfo $fallbackInfo 6>&1
        }

        $output = & $module $scriptBlock $pkgId $details $fallback
        $outputStr = $output | Out-String

        $outputStr | Should -Match "💾 Source:"
        $outputStr | Should -Match "winget"
    }

    It "Displays explicit Command section at the bottom" {
        $pkgId = "Microsoft.PowerToys"
        $details = @{
            "Microsoft.PowerToys" = @{
                Id = "Microsoft.PowerToys"
                Description = "System utilities"
            }
        }

        $module = Get-Module WingetBatch
        $scriptBlock = {
            param($id, $map)
            Show-WingetPackageDetails -PackageIds @($id) -DetailsMap $map 6>&1
        }

        $output = & $module $scriptBlock $pkgId $details
        $outputStr = $output | Out-String

        $outputStr | Should -Match "💻 Command:"
        $outputStr | Should -Match "winget install --id `"$pkgId`" -e"
    }
}
