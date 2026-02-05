
$iterations = 50
$pageSize = 100
$dummyData = 1..$pageSize

Write-Host "Benchmarking inefficient array addition..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$allCommits = @()
for ($i = 0; $i -lt $iterations; $i++) {
    $allCommits += $dummyData
}
$sw.Stop()
Write-Host "Inefficient method took: $($sw.ElapsedMilliseconds) ms"
Write-Host "Count: $($allCommits.Count)"

Write-Host "`nBenchmarking Generic List..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$allCommitsList = [System.Collections.Generic.List[Object]]::new()
for ($i = 0; $i -lt $iterations; $i++) {
    $allCommitsList.AddRange($dummyData)
}
$sw.Stop()
Write-Host "Generic List method took: $($sw.ElapsedMilliseconds) ms"
Write-Host "Count: $($allCommitsList.Count)"
