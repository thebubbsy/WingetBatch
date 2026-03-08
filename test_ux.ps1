Import-Module ./WingetBatch.psm1 -Force

$pkgId = "Test.Package"
$details = @{
    "Test.Package" = @{
        Id = "Test.Package"
        Description = "A test package description."
        Version = "1.2.3"
        Category = "Developer Tools"
        Pricing = "Free"
        Publisher = "Test Publisher"
        Installer = "EXE"
        Moniker = "testpkg"
        Homepage = "https://example.com"
        PublisherGitHub = "https://github.com/example/test"
        LicenseUrl = "https://example.com/license"
        PrivacyUrl = "https://example.com/privacy"
    }
}

$module = Get-Module WingetBatch
$scriptBlock = {
    param($id, $map)
    # Redirect Write-Host (stream 6) to success stream
    Show-WingetPackageDetails -PackageIds @($id) -DetailsMap $map 6>&1
}

$output = & $module $scriptBlock $pkgId $details
$output | Out-String | Write-Host
