$searchQueries = 1..50 # Simulate 50 search terms
$packagesPerQuery = 1..100 # Simulate 100 packages per query

Write-Host "Benchmarking Install-WingetAll logic..."

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$allPackages = @()
foreach ($query in $searchQueries) {
    # Simulate finding packages
    $uniqueQueryPackages = $packagesPerQuery | ForEach-Object {
        [PSCustomObject]@{ Id = "Pkg.$query.$_"; Name = "Package $query $_" }
    }
    $allPackages += $uniqueQueryPackages
}
$sw.Stop()
Write-Host "Inefficient (Array +=) took: $($sw.ElapsedMilliseconds) ms. Count: $($allPackages.Count)"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$allPackagesList = [System.Collections.Generic.List[Object]]::new()
foreach ($query in $searchQueries) {
    # Simulate finding packages
    $uniqueQueryPackages = $packagesPerQuery | ForEach-Object {
        [PSCustomObject]@{ Id = "Pkg.$query.$_"; Name = "Package $query $_" }
    }
    $allPackagesList.AddRange($uniqueQueryPackages)
}
$sw.Stop()
Write-Host "Optimized (List.AddRange) took: $($sw.ElapsedMilliseconds) ms. Count: $($allPackagesList.Count)"
