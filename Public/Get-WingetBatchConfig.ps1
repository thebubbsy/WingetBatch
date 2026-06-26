function Get-WingetBatchConfig {
    <#
    .SYNOPSIS
        Retrieve WingetBatch global settings.

    .DESCRIPTION
        Gets the current module-level configuration.

    .EXAMPLE
        Get-WingetBatchConfig
    #>
    [CmdletBinding()]
    param()

    $configPath = Join-Path (Get-WingetBatchConfigDir) "config.json"
    
    if (Test-Path $configPath) {
        Get-Content $configPath -Raw | ConvertFrom-Json
    } else {
        Write-Warning "No configuration found."
    }
}
