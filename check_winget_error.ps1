
$output = winget show --id "NonExistentPackage" 2>&1
Write-Host "Type: $($output.GetType().FullName)"
if ($output -is [array]) {
    Write-Host "Count: $($output.Count)"
    if ($output.Count -gt 0) {
        Write-Host "Item 0 Type: $($output[0].GetType().FullName)"
    }
}
