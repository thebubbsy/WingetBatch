function ConvertTo-WingetActionResult {
    <#
    .SYNOPSIS
        Normalize a Microsoft.WinGet.Client install/update/uninstall result.

    .DESCRIPTION
        Install-WinGetPackage, Update-WinGetPackage and Uninstall-WinGetPackage do not
        throw when the installer fails - they return a result object whose Status is
        something other than 'Ok'. This turns that object into a flat result that
        callers can trust.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        $Result,

        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Update', 'Uninstall')]
        [string]$Action
    )

    if ($null -eq $Result) {
        return [PSCustomObject]@{
            Id             = $Id
            Action         = $Action
            Succeeded      = $false
            Status         = 'NoResult'
            RebootRequired = $false
            Message        = 'WinGet returned no result.'
        }
    }

    # Cmdlets occasionally emit more than one object; the result is the last one
    $r = @($Result)[-1]
    $status = [string]$r.Status

    $succeeded = $status -eq 'Ok'
    $message = $null

    # Updating something that is already current is not a failure
    if (-not $succeeded -and $Action -eq 'Update' -and $status -eq 'NoApplicableUpgrade') {
        $succeeded = $true
        $message = 'Already up to date.'
    }

    if (-not $succeeded) {
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add($(if ($status) { $status } else { 'Failed' }))
        if ($r.InstallerErrorCode) { $parts.Add("installer exit code $($r.InstallerErrorCode)") }
        if ($r.UninstallerErrorCode) { $parts.Add("uninstaller exit code $($r.UninstallerErrorCode)") }
        if ($r.ExtendedErrorCode -and $r.ExtendedErrorCode.Message) { $parts.Add($r.ExtendedErrorCode.Message) }
        $message = $parts -join ' - '
    }

    [PSCustomObject]@{
        Id             = $Id
        Action         = $Action
        Succeeded      = $succeeded
        Status         = $(if ($status) { $status } else { 'Unknown' })
        RebootRequired = [bool]$r.RebootRequired
        Message        = $message
    }
}
