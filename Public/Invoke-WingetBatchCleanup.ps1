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
    
    # Clean orphaned jobs from current session
    $jobs = Get-Job -ErrorAction SilentlyContinue | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }
    if ($jobs) {
        $jobs | Remove-Job -Force
    }
    
    $mbFreed = [math]::Round($bytesFreed / 1MB, 2)
    Write-Host "Cleanup complete. Freed $mbFreed MB of cache." -ForegroundColor Green
}
