function Get-PackageDetailsCache {
    <#
    .SYNOPSIS
        Retrieve cached package details.

    .DESCRIPTION
        Internal function to get cached package details from JSON file.
        Cache expires after 30 days.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId
    )

    $cacheFile = Join-Path (Get-WingetBatchConfigDir) "package_cache.json"

    if (-not (Test-Path $cacheFile)) {
        return $null
    }

    try {
        $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $packageCache = $cache.PSObject.Properties[$PackageId]

        if ($packageCache) {
            $cachedDate = [DateTime]$packageCache.CachedDate
            $daysSinceCached = ((Get-Date) - $cachedDate).TotalDays

            if ($daysSinceCached -lt 30) {
                return $packageCache.Details
            }
        }
    }
    catch {
        # Ignore cache read errors
    }

    return $null
}
