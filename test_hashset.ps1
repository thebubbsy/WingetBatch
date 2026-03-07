$packages = @()
for ($i = 0; $i -lt 5000; $i++) {
    $packages += [PSCustomObject]@{ Id = "Pkg.$($i % 1000)"; Name = "Package $i" }
}

Write-Host "Benchmarking Group-Object..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$unique1 = $packages | Group-Object Id | ForEach-Object { $_.Group[0] }
$sw.Stop()
Write-Host "Group-Object took: $($sw.ElapsedMilliseconds) ms. Count: $($unique1.Count)"

Write-Host "Benchmarking HashSet..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$unique2 = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($pkg in $packages) {
    if ($seen.Add($pkg.Id)) {
        $unique2.Add($pkg)
    }
}
$sw.Stop()
Write-Host "HashSet took: $($sw.ElapsedMilliseconds) ms. Count: $($unique2.Count)"
