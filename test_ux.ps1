$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module "$PSScriptRoot/WingetBatch.psd1" -Force

$pkgId = "Microsoft.PowerToys"
$details = @{
    "Microsoft.PowerToys" = @{
        Id = "Microsoft.PowerToys"
        Name = "PowerToys"
        Version = "0.75.0"
        Description = "Microsoft PowerToys is a set of utilities for power users to tune and streamline their Windows experience for greater productivity."
        Publisher = "Microsoft Corporation"
        Tags = @("utility", "powertoys")
        Homepage = "https://github.com/microsoft/PowerToys"
        Installer = "msix"
        License = "MIT"
    }
}
$fallbackInfo = @()
$fallbackMap = @{}

$module = Get-Module WingetBatch
$scriptBlock = {
    param($id, $map, $fi, $fm)
    Show-WingetPackageDetails -PackageIds @($id) -DetailsMap $map -FallbackInfo $fi -FallbackMap $fm
}
& $module $scriptBlock $pkgId $details $fallbackInfo $fallbackMap
