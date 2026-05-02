function Export-WingetBatchConfig {
    <#
    .SYNOPSIS
        Export WingetBatch configuration and caches.
    
    .DESCRIPTION
        Compresses the user's ~/.wingetbatch directory into a zip archive.
        This includes the GitHub token, rate limits, caches, and general configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    $configDir = Get-WingetBatchConfigDir
    if (Test-Path $configDir) {
        # Ensure path has .zip extension
        if (-not $Path.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
            $Path = "$Path.zip"
        }
        Compress-Archive -Path "$configDir\*" -DestinationPath $Path -Force
        Write-Host "Exported WingetBatch configuration to $Path" -ForegroundColor Green
    } else {
        Write-Warning "No WingetBatch configuration found to export."
    }
}
