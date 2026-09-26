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

    $config = Get-WingetBatchConfigData

    if ($PSBoundParameters.ContainsKey('SearchMatchOption')) {
        $config['SearchMatchOption'] = $SearchMatchOption
    }

    Save-WingetBatchConfigData -Config $config
    Write-Host "WingetBatch configuration updated successfully." -ForegroundColor Green
}
