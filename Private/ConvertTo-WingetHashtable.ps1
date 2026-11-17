function ConvertTo-WingetHashtable {
    <#
    .SYNOPSIS
        Recursively convert PSCustomObject values (such as ConvertFrom-Json output) into hashtables.

    .DESCRIPTION
        Windows PowerShell 5.1 does not support ConvertFrom-Json -AsHashtable.
        This helper normalizes parsed JSON objects into hashtables across PS 5.1 and 7+.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object]$InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }
        if ($InputObject -is [System.Collections.IDictionary]) {
            $ht = @{}
            foreach ($key in $InputObject.Keys) {
                $ht[$key] = ConvertTo-WingetHashtable -InputObject $InputObject[$key]
            }
            return $ht
        }
        if ($InputObject -is [PSCustomObject]) {
            $ht = @{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                $ht[$prop.Name] = ConvertTo-WingetHashtable -InputObject $prop.Value
            }
            return $ht
        }
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $list = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $InputObject) {
                $list.Add((ConvertTo-WingetHashtable -InputObject $item))
            }
            return ,$list.ToArray()
        }
        return $InputObject
    }
}
