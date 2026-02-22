
Import-Module "$PSScriptRoot/../WingetBatch.psm1" -Force

Describe "Show-WingetPackageDetails Verification" {
    It "Displays the installation command" {
        $pkgId = "Test.Pkg"
        $details = @{
            "Test.Pkg" = @{
                Id = "Test.Pkg"
                Description = "Test Description"
                Version = "1.0.0"
            }
        }

        $module = Get-Module WingetBatch
        $scriptBlock = {
            param($id, $map)
            Show-WingetPackageDetails -PackageIds @($id) -DetailsMap $map 6>&1
        }

        $output = & $module $scriptBlock $pkgId $details
        $outputStr = $output | Out-String

        $outputStr | Should -Match "Command:"
        $outputStr | Should -Match "winget install --id Test.Pkg -e"
    }
}
