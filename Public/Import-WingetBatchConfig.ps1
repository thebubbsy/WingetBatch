function Import-WingetBatchConfig {
    <#
    .SYNOPSIS
        Import WingetBatch configuration and caches from a zip archive.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    if (-not (Test-Path $Path)) {
        Write-Error "Backup file not found at $Path"
        return
    }
    $configDir = Get-WingetBatchConfigDir
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir | Out-Null
    }
    Expand-Archive -Path $Path -DestinationPath $configDir -Force
    Write-Host "Imported WingetBatch configuration from $Path" -ForegroundColor Green
}

