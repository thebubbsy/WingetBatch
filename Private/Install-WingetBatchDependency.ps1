function Install-WingetBatchDependency {
    <#
    .SYNOPSIS
        Install or update a PowerShell Gallery module without interactive prompts.

    .DESCRIPTION
        Works with both PSResourceGet (Install-PSResource, the default in newer
        PowerShell, where Install-Module may be an alias that prompts for trust)
        and classic PowerShellGet. Throws on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Update
    )

    if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
        if ($Update -and (Get-Command Update-PSResource -ErrorAction SilentlyContinue) -and (Get-InstalledPSResource -Name $Name -ErrorAction SilentlyContinue)) {
            Update-PSResource -Name $Name -TrustRepository -AcceptLicense -Quiet -ErrorAction Stop
        }
        else {
            Install-PSResource -Name $Name -Scope CurrentUser -TrustRepository -AcceptLicense -Quiet -Reinstall:$Update -ErrorAction Stop
        }
    }
    elseif ($Update) {
        Update-Module -Name $Name -Force -AcceptLicense -ErrorAction Stop
    }
    else {
        Install-Module -Name $Name -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber -ErrorAction Stop
    }
}
