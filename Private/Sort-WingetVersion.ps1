function Sort-WingetVersion {
    <#
    .SYNOPSIS
        Sort objects (or strings) by package version using Compare-WingetVersion.

    .PARAMETER Property
        Property holding the version. Omit to sort plain strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [string]$Property,

        [switch]$Descending
    )

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $InputObject) { if ($null -ne $item) { $list.Add($item) } }

    $sign = if ($Descending) { -1 } else { 1 }
    $list.Sort([System.Comparison[object]] {
        param($x, $y)
        $vx = if ($Property) { [string]$x.$Property } else { [string]$x }
        $vy = if ($Property) { [string]$y.$Property } else { [string]$y }
        $sign * (Compare-WingetVersion -ReferenceVersion $vx -DifferenceVersion $vy)
    })

    $list.ToArray()
}
