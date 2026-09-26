function Invoke-WingetBatchCleanup {
    <#
    .SYNOPSIS
        Clean up WingetBatch caches and orphaned jobs.
    #>
    [CmdletBinding()]
    param()
    $configDir = Get-WingetBatchConfigDir
    $cacheFile = Join-Path $configDir "package_cache.json"
    $updateCacheFile = Join-Path $configDir "update_cache.json"
    
    $bytesFreed = 0
    if (Test-Path $cacheFile) {
        $bytesFreed += (Get-Item $cacheFile).Length
        Remove-Item $cacheFile -Force
    }
    if (Test-Path $updateCacheFile) {
        $bytesFreed += (Get-Item $updateCacheFile).Length
        Remove-Item $updateCacheFile -Force
    }
    
    # Clean up finished WingetBatch jobs only (leave the user's own jobs alone)
    $jobs = Get-Job -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in 'WingetBatchDetails', 'WingetUpdateCheck' -and $_.State -in @('Completed', 'Failed', 'Stopped')
    }
    if ($jobs) {
        $jobs | Remove-Job -Force
    }
    
    $mbFreed = [math]::Round($bytesFreed / 1MB, 2)
    Write-Host "Cleanup complete. Freed $mbFreed MB of cache." -ForegroundColor Green
}

