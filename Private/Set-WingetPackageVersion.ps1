function Set-WingetPackageVersion {
    <#
    .SYNOPSIS
        Move an installed package to an exact version (up or down) and verify it.

    .DESCRIPTION
        Installing an older version on top of a newer one is unreliable: MSI packages
        usually refuse while WinGet still reports 'Ok', and a package can switch
        installer technology between versions (VLC: MSI 3.0.23 vs EXE 3.0.21), which
        leaves two registered copies sharing one folder. So downgrades remove the
        package first and then install the pinned version. Every path ends by checking
        the version WinGet actually sees.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Version,
        [string]$Source
    )

    $getInstalled = {
        @(Microsoft.WinGet.Client\Get-WinGetPackage -Id $Id -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue) |
            ForEach-Object { [string]$_.InstalledVersion }
    }
    $isTarget = { param($v) $v -and (Compare-WingetVersion -ReferenceVersion $v -DifferenceVersion $Version) -eq 0 }
    $fail = {
        param($status, $message)
        [PSCustomObject]@{ Id = $Id; Action = 'Install'; Succeeded = $false; Status = $status; RebootRequired = $false; Message = $message }
    }

    # Remove every installed copy. The COM API cannot target one of several installed
    # versions (it returns MULTIPLE_APPLICATIONS_FOUND), so fall back to the CLI.
    $removeAll = {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        # Uninstalling one copy can re-expose another registration, so re-check a few times
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            if (@(& $getInstalled).Count -eq 0) { return $true }
            $r = Invoke-WingetPackageAction -Action Uninstall -Id $Id -Source $Source -Options @{ Mode = 'Silent' }
            if (-not $r.Succeeded -and $winget) {
                & $winget.Source uninstall --id $Id --exact --all-versions --silent --disable-interactivity --accept-source-agreements 2>&1 | Out-Null
            }
        }
        return (@(& $getInstalled).Count -eq 0)
    }

    $current = @(& $getInstalled)
    if ($current.Count -eq 1 -and (& $isTarget $current[0])) {
        return [PSCustomObject]@{ Id = $Id; Action = 'Install'; Succeeded = $true; Status = 'Ok'; RebootRequired = $false; Message = 'Already at target version.' }
    }

    $isDowngrade = @($current | Where-Object { (Compare-WingetVersion -ReferenceVersion $_ -DifferenceVersion $Version) -gt 0 }).Count -gt 0
    if ($isDowngrade -or $current.Count -gt 1) {
        Write-Verbose "Removing $Id ($($current -join ', ')) before installing $Version"
        if (-not (& $removeAll)) {
            return (& $fail 'UninstallFailed' "Could not remove the installed version(s) $($current -join ', ') before installing $Version.")
        }
        $result = Invoke-WingetPackageAction -Action Install -Id $Id -Version $Version -Source $Source -Options @{ Mode = 'Silent' }
    }
    else {
        $result = Invoke-WingetPackageAction -Action Install -Id $Id -Version $Version -Source $Source -Options @{ Mode = 'Silent'; Force = $true }
    }

    if ($result.Succeeded) {
        $after = @(& $getInstalled)
        if ($after.Count -ne 1 -or -not (& $isTarget $after[0])) {
            $result.Succeeded = $false
            $result.Status = 'VersionMismatch'
            $result.Message = "WinGet reported success but installed version(s) are: $(if ($after) { $after -join ', ' } else { 'none' }), expected $Version."
        }
    }
    return $result
}
