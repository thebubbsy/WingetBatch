
function global:winget {
    param([Parameter(ValueFromRemainingArguments=$true)]$Args)
    # Mock winget output as array of strings
    return @("Line 1", "Line 2", "Line 3")
}

$output = winget show --id "Test"
Write-Host "Type: $($output.GetType().FullName)"
if ($output -is [array]) {
    Write-Host "Is Array: Yes"
    Write-Host "Count: $($output.Count)"
} else {
    Write-Host "Is Array: No"
}
