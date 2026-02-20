
Import-Module ./WingetBatch.psm1 -Force

$output = @"
Found MongoDB Shell [MongoDB.Shell]
Version: 2.3.2
Publisher: MongoDB, Inc.
"@

# Invoke internal function correctly
$result = & (Get-Module WingetBatch) {
    param($out)
    Parse-WingetShowOutput -Output $out -PackageId "Test"
} $output

Write-Host "Result Version: $($result.Version)"
Write-Host "Result Publisher: $($result.Publisher)"
