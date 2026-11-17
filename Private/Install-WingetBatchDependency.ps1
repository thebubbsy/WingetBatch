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
        $cmd = Get-Command Update-Module -ErrorAction Stop
        $params = @{ Name = $Name; Force = $true; ErrorAction = 'Stop' }
        if ($cmd.Parameters.ContainsKey('AcceptLicense')) { $params['AcceptLicense'] = $true }
        Update-Module @params
    }
    else {
        $cmd = Get-Command Install-Module -ErrorAction Stop
        $params = @{ Name = $Name; Scope = 'CurrentUser'; Force = $true; ErrorAction = 'Stop' }
        if ($cmd.Parameters.ContainsKey('SkipPublisherCheck')) { $params['SkipPublisherCheck'] = $true }
        if ($cmd.Parameters.ContainsKey('AllowClobber')) { $params['AllowClobber'] = $true }
        Install-Module @params
    }
}
