function Start-PackageDetailJobs {
    param(
        [string[]]$PackageIds,
        [string]$ConfigDir
    )

    $maxConcurrentJobs = 100 # Increased from 10 to allow higher concurrency
    $totalPackages = $PackageIds.Count

    if ($totalPackages -eq 0) { return @(), @{} }

    $packagesPerJob = [Math]::Ceiling($totalPackages / $maxConcurrentJobs)
    if ($packagesPerJob -lt 1) { $packagesPerJob = 1 }

    $actualJobCount = [Math]::Ceiling($totalPackages / $packagesPerJob)

    $jobs = [System.Collections.Generic.List[Object]]::new()
    $jobPackageMap = @{}

    $jobScript = {
        param($packageList, $cacheDir, $ParseSB)
        $results = @{}

        # Define Parse-WingetShowOutput in the job scope from the passed script block
        if ($ParseSB) {
            Set-Item -Path function:Parse-WingetShowOutput -Value $ParseSB
        }

        $cacheFile = Join-Path $cacheDir "package_cache.json"
        $localCache = @{}

        # Read cache once at start of job - optimization to avoid repeated file I/O
        if (Test-Path $cacheFile) {
            try {
                $cacheJson = Get-Content $cacheFile -Raw | ConvertFrom-Json
                if ($cacheJson) {
                    # Convert to hashtable for fast O(1) lookup
                    # Iterate properties to handle both PSObject (from JSON object) and Hashtable
                    $cacheJson.PSObject.Properties | ForEach-Object {
                        $localCache[$_.Name] = $_.Value
                    }
                }
            }
            catch { }
        }

        foreach ($pkgIdItem in $packageList) {
            # Ensure packageId is a string (handle potential array wrapping artifacts)
            $packageId = [string]$pkgIdItem
            $cachedInfo = $null

            # Try to get from cache first (check local hashtable)
            if ($localCache.ContainsKey($packageId)) {
                $entry = $localCache[$packageId]
                # Check for cached date on the entry object
                if ($entry -and $entry.CachedDate) {
                    try {
                        $cachedDate = [DateTime]$entry.CachedDate
                        $daysSinceCached = ((Get-Date) - $cachedDate).TotalDays

                        if ($daysSinceCached -lt 30) {
                            $cachedInfo = $entry.Details
                        }
                    }
                    catch { }
                }
            }

            if ($cachedInfo) {
                # Use cached data
                $results[$packageId] = $cachedInfo
                continue
            }

            # Not in cache, fetch from winget
            $output = winget show --id $packageId 2>&1 | Out-String

            # Parse winget show output - capture ALL available fields
            $info = Parse-WingetShowOutput -Output $output -PackageId $packageId

            $results[$packageId] = $info
        }

        return $results
    }

    for ($i = 0; $i -lt $actualJobCount; $i++) {
        $startIndex = $i * $packagesPerJob
        $endIndex = [Math]::Min($startIndex + $packagesPerJob - 1, $totalPackages - 1)
        if ($startIndex -gt $endIndex) { break }

        $packageBatch = $PackageIds[$startIndex..$endIndex]

        $job = Start-WingetBatchJob -ScriptBlock $jobScript -ArgumentList (,$packageBatch), $ConfigDir, $function:Parse-WingetShowOutput
        $jobs.Add($job)
        $jobPackageMap[$job.Id] = $packageBatch
    }

    return $jobs, $jobPackageMap
}
