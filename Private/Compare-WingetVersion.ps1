function Compare-WingetVersion {
    <#
    .SYNOPSIS
        Compare two package version strings. Returns -1, 0 or 1.

    .DESCRIPTION
        Package versions are not always valid [version] values ("1.2.3.4.5",
        "2024.01", "1.0.0-beta2"), and sorting them as text puts 9.0 above 10.0.
        Segments are split on . - + _ and compared numerically when both are numbers.
        A numeric segment beats a text segment, and a release beats its pre-release
        ("1.0" > "1.0-beta").
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$ReferenceVersion,
        [AllowEmptyString()][AllowNull()][string]$DifferenceVersion
    )

    # Split on separators, then between letters and digits ("beta10" -> "beta", "10")
    $split = {
        param($v)
        if (-not $v) { return @() }
        @($v.Trim().TrimStart('vV') -split '[.\-+_ ]' | ForEach-Object { $_ -split '(?<=\d)(?=\D)|(?<=\D)(?=\d)' } | Where-Object { $_ -ne '' })
    }
    $a = & $split $ReferenceVersion
    $b = & $split $DifferenceVersion

    $max = [Math]::Max($a.Count, $b.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $x = if ($i -lt $a.Count) { $a[$i] } else { $null }
        $y = if ($i -lt $b.Count) { $b[$i] } else { $null }

        $xNum = $null -ne $x -and $x -match '^\d+$'
        $yNum = $null -ne $y -and $y -match '^\d+$'

        # A missing segment counts as 0 against a number, and as "release" against text
        if ($null -eq $x) { if ($yNum) { $x = '0'; $xNum = $true } else { return 1 } }
        if ($null -eq $y) { if ($xNum) { $y = '0'; $yNum = $true } else { return -1 } }

        if ($xNum -and $yNum) {
            $xt = $x.TrimStart('0'); $yt = $y.TrimStart('0')
            if ($xt.Length -ne $yt.Length) { return [Math]::Sign($xt.Length - $yt.Length) }
            $c = [string]::CompareOrdinal($xt, $yt)
            if ($c -ne 0) { return [Math]::Sign($c) }
        }
        elseif ($xNum) { return 1 }
        elseif ($yNum) { return -1 }
        else {
            $c = [string]::Compare($x, $y, [System.StringComparison]::OrdinalIgnoreCase)
            if ($c -ne 0) { return [Math]::Sign($c) }
        }
    }
    return 0
}
