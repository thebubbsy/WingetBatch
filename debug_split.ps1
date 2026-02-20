
$Output = @"
Found MongoDB Shell [MongoDB.Shell]
Version: 2.3.2
Publisher: MongoDB, Inc.
"@

Write-Host "Original Type: $($Output.GetType().Name)"

if ($Output -is [string]) {
    $lines = $Output.Split([char[]]@("`n", "`r"), [System.StringSplitOptions]::RemoveEmptyEntries)
} elseif ($Output -is [System.Collections.IEnumerable]) {
    $lines = $Output
} else {
    $lines = @($Output)
}

Write-Host "Lines Count: $($lines.Count)"
foreach ($line in $lines) {
    Write-Host "Line: '$line'"
    $colonIndex = $line.IndexOf(':')
    if ($colonIndex -gt 0) {
        $key = $line.Substring(0, $colonIndex).Trim()
        $value = $line.Substring($colonIndex + 1).Trim()
        Write-Host "  Key: '$key' Value: '$value'"
    }
}
