function Start-PackageDetailJobs {
    param(
        [string[]]$PackageIds,
        [string]$ConfigDir
    )

    $maxConcurrentJobs = 100
    $totalPackages = $PackageIds.Count

    if ($totalPackages -eq 0) { return @(), @{} }

    $packagesPerJob = [Math]::Ceiling($totalPackages / $maxConcurrentJobs)
    if ($packagesPerJob -lt 1) { $packagesPerJob = 1 }

    $actualJobCount = [Math]::Ceiling($totalPackages / $packagesPerJob)

    $jobs = [System.Collections.Generic.List[Object]]::new()
    $jobPackageMap = @{}

    # Resolve winget.exe path for detail fetching (COM API has limited fields)
    $wingetExe = $null
    $testPaths = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "C:\Users\$env:USERNAME\AppData\Local\Microsoft\WindowsApps\winget.exe"
    )
    foreach ($tp in $testPaths) {
        if (Test-Path $tp) { $wingetExe = $tp; break }
    }
    # Also check if winget is in PATH
    if (-not $wingetExe) {
        $cmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($cmd) { $wingetExe = $cmd.Source }
    }

    $jobScript = {
        param($packageList, $cacheDir, $ParseSB, $WingetPath)
        $results = @{}

        # Define Parse-WingetShowOutput in the job scope from the passed script block
        if ($ParseSB) {
            Set-Item -Path function:Parse-WingetShowOutput -Value $ParseSB
        }

        $cacheFile = Join-Path $cacheDir "package_cache.json"
        $localCache = @{}

        # Read cache once at start of job
        if (Test-Path $cacheFile) {
            try {
                $cacheJson = Get-Content $cacheFile -Raw | ConvertFrom-Json
                if ($cacheJson) {
                    $cacheJson.PSObject.Properties | ForEach-Object {
                        $localCache[$_.Name] = $_.Value
                    }
                }
            }
            catch { }
        }

        foreach ($pkgIdItem in $packageList) {
            $packageId = [string]$pkgIdItem
            $cachedInfo = $null

            # Try to get from cache first
            if ($localCache.ContainsKey($packageId)) {
                $entry = $localCache[$packageId]
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
                $results[$packageId] = $cachedInfo
                continue
            }

            # Not in cache - try winget.exe for rich details, fall back to COM API for basic info
            $info = $null

            if ($WingetPath -and (Test-Path $WingetPath)) {
                try {
                    $output = & $WingetPath show --id $packageId --no-progress --disable-interactivity 2>&1 | Out-String
                    $info = Parse-WingetShowOutput -Output $output -PackageId $packageId
                }
                catch {
                    # Fall through to COM API
                }
            }

            if (-not $info -or -not $info.Version) {
                # Fallback: Use COM API (limited fields but always works)
                try {
                    Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
                    $comResult = Find-WinGetPackage -Id $packageId -Exact -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($comResult) {
                        $info = @{
                            Id = $packageId
                            Version = $comResult.Version
                            Publisher = $null
                            PublisherName = $null
                            PublisherUrl = $null
                            PublisherGitHub = $null
                            Author = $null
                            Homepage = $null
                            Description = $null
                            Category = $null
                            Tags = @()
                            License = $null
                            LicenseUrl = $null
                            Copyright = $null
                            CopyrightUrl = $null
                            PrivacyUrl = $null
                            PackageUrl = $null
                            ReleaseNotes = $null
                            ReleaseNotesUrl = $null
                            Installer = $null
                            Pricing = $null
                            StoreLicense = $null
                            FreeTrial = $null
                            AgeRating = $null
                            Moniker = $null
                            Name = $comResult.Name
                        }
                    }
                }
                catch { }
            }

            if (-not $info) {
                $info = @{ Id = $packageId }
            }

            $results[$packageId] = $info
        }

        return $results
    }

    for ($i = 0; $i -lt $actualJobCount; $i++) {
        $startIndex = $i * $packagesPerJob
        $endIndex = [Math]::Min($startIndex + $packagesPerJob - 1, $totalPackages - 1)
        if ($startIndex -gt $endIndex) { break }

        $packageBatch = $PackageIds[$startIndex..$endIndex]

        $job = Start-WingetBatchJob -ScriptBlock $jobScript -ArgumentList (,$packageBatch), $ConfigDir, $function:Parse-WingetShowOutput, $wingetExe
        $jobs.Add($job)
        $jobPackageMap[$job.Id] = $packageBatch
    }

    return $jobs, $jobPackageMap
}
