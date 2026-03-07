$searchQueries = 1..5 # Simulate 5 search terms
$packagesPerQuery = 1..1000 # Simulate 1000 packages per query

Write-Host "Benchmarking deduplication logic..."

$allPackages = @()
foreach ($query in $searchQueries) {
    # Simulate finding packages with 50% duplicates
    $uniqueQueryPackages = $packagesPerQuery | ForEach-Object {
        [PSCustomObject]@{ Id = "Pkg.$query.$($_ % 500)"; Name = "Package $query $_" }
    }
    $allPackages += $uniqueQueryPackages
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$result1 = $allPackages | Group-Object Id | ForEach-Object { $_.Group[0] }
$sw.Stop()
Write-Host "Inefficient (Group-Object) took: $($sw.ElapsedMilliseconds) ms. Count: $($result1.Count)"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$result2 = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($pkg in $allPackages) {
    if ($seen.Add($pkg.Id)) {
        $result2.Add($pkg)
    }
}
$sw.Stop()
Write-Host "Optimized (HashSet) took: $($sw.ElapsedMilliseconds) ms. Count: $($result2.Count)"
