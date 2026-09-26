function Get-WingetSourceIndexAge {
    <#
    .SYNOPSIS
        How old the local winget source index is, as a TimeSpan ($null if unknown).

    .DESCRIPTION
        Current WinGet versions ship the index inside the Microsoft.Winget.Source app
        package (index.db); older ones kept source.db under App Installer's LocalState.
    #>
    [CmdletBinding()]
    param()

    $candidates = [System.Collections.Generic.List[string]]::new()
    try {
        $pkg = Get-AppxPackage -Name 'Microsoft.Winget.Source' -ErrorAction Stop |
            Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg -and $pkg.InstallLocation) {
            $candidates.Add((Join-Path $pkg.InstallLocation 'Public\index.db'))
            $candidates.Add((Join-Path $pkg.InstallLocation 'index.db'))
        }
    }
    catch {
        Write-Verbose "Get-AppxPackage unavailable: $_"
    }
    $candidates.Add("$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\Microsoft.Winget.Source_8wekyb3d8bbwe\winget\source.db")

    foreach ($path in $candidates) {
        if (Test-Path $path) {
            return (Get-Date) - (Get-Item $path).LastWriteTime
        }
    }
    return $null
}
