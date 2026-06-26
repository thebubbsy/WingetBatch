function Set-WingetBatchConfig {
    <#
    .SYNOPSIS
        Configure WingetBatch global settings.

    .DESCRIPTION
        Sets module-level configuration options such as the default SearchMatchOption.

    .PARAMETER SearchMatchOption
        Sets the default match behavior for search.
        Valid values: ContainsCaseInsensitive (default), EqualsCaseInsensitive, StartsWithCaseInsensitive.

    .EXAMPLE
        Set-WingetBatchConfig -SearchMatchOption EqualsCaseInsensitive
        Configures the module to strictly match package names instead of wildcard searching.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("ContainsCaseInsensitive", "EqualsCaseInsensitive", "StartsWithCaseInsensitive")]
        [string]$SearchMatchOption
    )

    $configDir = Get-WingetBatchConfigDir
    $configPath = Join-Path $configDir "config.json"
    
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $config = @{}
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            # Convert PSObject back to hashtable
            $hash = @{}
            $config.psobject.properties | ForEach-Object { $hash[$_.Name] = $_.Value }
            $config = $hash
        } catch {
            Write-Warning "Existing config corrupt. Starting fresh."
        }
    }

    if ($PSBoundParameters.ContainsKey('SearchMatchOption')) {
        $config.SearchMatchOption = $SearchMatchOption
    }

    $config | ConvertTo-Json -Depth 5 | Out-File $configPath -Encoding UTF8
    Write-Host "WingetBatch configuration updated successfully." -ForegroundColor Green
}
