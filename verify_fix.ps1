try {
    $list = [System.Collections.Generic.List[Object]]::new()

    Write-Host "Testing single item..."
    $single = [PSCustomObject]@{ Id = "Single" }
    $list.AddRange(@($single))
    Write-Host "Single item added successfully. Count: $($list.Count)"

    Write-Host "Testing null/empty..."
    $empty = $null
    $list.AddRange(@($empty))
    Write-Host "Empty item added successfully (should be no-op or empty array). Count: $($list.Count)"

    Write-Host "Testing array..."
    $array = 1..3
    $list.AddRange(@($array))
    Write-Host "Array added successfully. Count: $($list.Count)"

    Write-Host "ALL TESTS PASSED"
}
catch {
    Write-Error "Test Failed: $_"
    exit 1
}
