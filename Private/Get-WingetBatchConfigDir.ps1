function Get-WingetBatchConfigDir {
    <#
    .SYNOPSIS
        Get the configuration directory path.

    .DESCRIPTION
        Internal function to get the path to the .wingetbatch configuration directory.
    #>
    if ($env:USERPROFILE) {
        $homeDir = $env:USERPROFILE
    } else {
        $homeDir = $HOME
    }
    return Join-Path $homeDir ".wingetbatch"
}
