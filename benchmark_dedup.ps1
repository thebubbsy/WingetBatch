
$count = 10000
$packages = [System.Collections.Generic.List[PSCustomObject]]::new()

# Create a list with duplicates
for ($i = 0; $i -lt $count; $i++) {
    $id = "Package.$($i % 100)" # 100 unique IDs repeated
    $packages.Add([PSCustomObject]@{
        Id = $id
        Name = "Name for $id"
        Version = "1.0.0"
    })
}

Write-Host "Benchmarking deduplication of $count items..."

# Original method: Group-Object
$sw1 = [System.Diagnostics.Stopwatch]::StartNew()
$unique1 = $packages | Group-Object Id | ForEach-Object { $_.Group[0] }
$sw1.Stop()
Write-Host "Group-Object took: $($sw1.ElapsedMilliseconds) ms"
Write-Host "Count: $($unique1.Count)"

# Optimized method: HashSet
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
$seen = [System.Collections.Generic.HashSet[string]]::new()
$unique2 = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($pkg in $packages) {
    if ($seen.Add($pkg.Id)) {
        $unique2.Add($pkg)
    }
}
$sw2.Stop()
Write-Host "HashSet took: $($sw2.ElapsedMilliseconds) ms"
Write-Host "Count: $($unique2.Count)"

# Optimized method: Hashtable (PowerShell native-ish)
$sw3 = [System.Diagnostics.Stopwatch]::StartNew()
$seenHash = @{}
$unique3 = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($pkg in $packages) {
    if (-not $seenHash.ContainsKey($pkg.Id)) {
        $seenHash[$pkg.Id] = $true
        $unique3.Add($pkg)
    }
}
$sw3.Stop()
Write-Host "Hashtable took: $($sw3.ElapsedMilliseconds) ms"
Write-Host "Count: $($unique3.Count)"
