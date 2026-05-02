function Set-PackageDetailsCache {
    <#
    .SYNOPSIS
        Store package details in cache.

    .DESCRIPTION
        Internal function to cache package details to JSON file with 30-day TTL.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId,

        [Parameter(Mandatory=$true)]
        [hashtable]$Details
    )

    $configDir = Get-WingetBatchConfigDir
    $cacheFile = Join-Path $configDir "package_cache.json"

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Load existing cache or create new
    $cache = @{}
    if (Test-Path $cacheFile) {
        try {
            $cacheJson = Get-Content $cacheFile -Raw | ConvertFrom-Json
            # Convert PSCustomObject to hashtable
            $cacheJson.PSObject.Properties | ForEach-Object {
                $cache[$_.Name] = $_.Value
            }
        }
        catch {
            # Start fresh if cache is corrupt
        }
    }

    # Add/update package entry
    $cache[$PackageId] = @{
        CachedDate = (Get-Date).ToString('o')
        Details = $Details
    }

    # Save cache
    try {
        $jsonContent = $cache | ConvertTo-Json -Depth 10 -Compress:$false
        [System.IO.File]::WriteAllText($cacheFile, $jsonContent, [System.Text.Encoding]::UTF8)
    }
    catch {
        Write-Verbose "Failed to write package cache: $_"
    }
}
