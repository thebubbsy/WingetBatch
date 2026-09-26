function Invoke-WingetPackageAction {
    <#
    .SYNOPSIS
        Install, update or uninstall one package and report whether it really worked.

    .DESCRIPTION
        Single entry point for package changes. Always calls the Microsoft.WinGet.Client
        cmdlets by their module-qualified name (other modules such as Cobalt export
        commands with the same names), matches the ID exactly instead of by substring,
        and returns a ConvertTo-WingetActionResult object instead of assuming success
        when no exception is thrown.

    .PARAMETER Options
        Optional install settings: Mode, Scope, Architecture, Override, Location,
        Force, SkipDependencies, AllowHashMismatch. Keys the target cmdlet does not
        support are ignored.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Update', 'Uninstall')]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [string]$Source,

        [Parameter()]
        [hashtable]$Options = @{}
    )

    $cmd = Get-Command -Name "Microsoft.WinGet.Client\$Action-WinGetPackage" -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [PSCustomObject]@{
            Id = $Id; Action = $Action; Succeeded = $false; Status = 'ModuleMissing'
            RebootRequired = $false; Message = 'Microsoft.WinGet.Client is not available.'
        }
    }

    $params = @{
        Id          = $Id
        MatchOption = 'EqualsCaseInsensitive'
        ErrorAction = 'Stop'
    }
    if ($Version -and $Version -ne 'latest') { $params['Version'] = $Version }
    if ($Source) { $params['Source'] = $Source }

    foreach ($key in $Options.Keys) {
        $value = $Options[$key]
        if ($null -eq $value -or ($value -is [string] -and $value -eq '')) { continue }
        if (-not $cmd.Parameters.ContainsKey($key)) { continue }
        if ($cmd.Parameters[$key].SwitchParameter) {
            if ([bool]$value) { $params[$key] = $true }
        }
        else {
            $params[$key] = $value
        }
    }

    # Installed copies of this exact ID. ARP\... and MSIX\... IDs make the -Id search
    # throw CatalogError, so fall back to listing everything and filtering.
    $findInstalled = {
        try {
            @(Microsoft.WinGet.Client\Get-WinGetPackage -Id $Id -MatchOption EqualsCaseInsensitive -ErrorAction Stop)
        }
        catch {
            @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq $Id })
        }
    }
    $countInstalled = { @(& $findInstalled).Count }
    $getVersion = { & $findInstalled | Select-Object -First 1 -ExpandProperty InstalledVersion }
    # Counted before an uninstall so we can confirm a copy went away
    $before = if ($Action -eq 'Uninstall') { & $countInstalled } else { 0 }
    $versionBefore = if ($Action -eq 'Update') { [string](& $getVersion) } else { $null }

    try {
        # Programs known only from Add/Remove Programs (ARP\...) or MSIX (MSIX\...) cannot
        # be found by ID search (CatalogError); act on the installed package object instead.
        $byObject = {
            $pkg = & $findInstalled | Select-Object -First 1
            if (-not $pkg) { throw "Package '$Id' is not installed." }
            $objParams = @{ PSCatalogPackage = $pkg; ErrorAction = 'Stop' }
            foreach ($k in $params.Keys) {
                if ($k -notin 'Id', 'MatchOption', 'Source', 'Version', 'ErrorAction') { $objParams[$k] = $params[$k] }
            }
            & $cmd @objParams
        }
        if ($Action -ne 'Install' -and $Id -match '^(ARP|MSIX)\\') {
            $result = & $byObject
        }
        else {
            try { $result = & $cmd @params }
            catch {
                if ($Action -ne 'Install' -and $_.Exception.Message -match 'CatalogError') { $result = & $byObject }
                else { throw }
            }
        }
        $normalized = ConvertTo-WingetActionResult -Result $result -Id $Id -Action $Action

        # Some uninstallers exit 0 without removing anything (WinGet then reports Ok),
        # and NSIS uninstallers finish a few seconds after returning. Confirm removal.
        if ($normalized.Succeeded -and $Action -eq 'Uninstall' -and $before -gt 0) {
            $deadline = (Get-Date).AddSeconds(30)
            while ((& $countInstalled) -ge $before -and (Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 3
            }
            if ((& $countInstalled) -ge $before) {
                $normalized.Succeeded = $false
                $normalized.Status = 'StillInstalled'
                $normalized.Message = "WinGet reported success, but $Id is still installed (the uninstaller did not remove it)."
            }
        }
        # An update that "succeeds" but leaves the same version installed (installer
        # declined, or WinGet mis-orders versions like "1.5.11+hash" vs "1.5.11")
        if ($normalized.Succeeded -and $Action -eq 'Update' -and $normalized.Status -eq 'Ok' -and $versionBefore) {
            $deadline = (Get-Date).AddSeconds(20)
            $versionAfter = [string](& $getVersion)
            while ($versionAfter -eq $versionBefore -and (Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 3
                $versionAfter = [string](& $getVersion)
            }
            if ($versionAfter -eq $versionBefore) {
                $normalized.Succeeded = $false
                $normalized.Status = 'NotUpdated'
                $normalized.Message = "WinGet reported success, but $Id is still at $versionBefore."
            }
        }
        $normalized
    }
    catch {
        [PSCustomObject]@{
            Id             = $Id
            Action         = $Action
            Succeeded      = $false
            Status         = 'Error'
            RebootRequired = $false
            Message        = $_.Exception.Message
        }
    }
}
