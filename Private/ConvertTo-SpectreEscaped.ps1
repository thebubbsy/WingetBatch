function ConvertTo-SpectreEscaped {
    <#
    .SYNOPSIS
        Escape special characters for Spectre Console markup.

    .DESCRIPTION
        Internal function to escape brackets so they are rendered literally in Spectre Console.
        [ becomes [[
        ] becomes ]]
    #>
    param(
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    if ($Text.IndexOf('[') -eq -1 -and $Text.IndexOf(']') -eq -1) { return $Text }
    return $Text.Replace('[', '[[').Replace(']', ']]')
}
