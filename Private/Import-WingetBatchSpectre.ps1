function Import-WingetBatchSpectre {
    <#
    .SYNOPSIS
        Safely import PwshSpectreConsole on PowerShell 7.4+ without triggering encoding warnings.

    .DESCRIPTION
        PwshSpectreConsole requires PowerShell 7.4+ (Core edition) and prints a large
        warning banner at import time if the host output encoding is not UTF-8.
        This helper skips import on Windows PowerShell 5.1, enables UTF-8 console
        encoding when supported, suppresses the import-time warning if UTF-8 cannot
        be applied, and returns $true when PwshSpectreConsole is loaded.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $isSupportedPs = ($PSVersionTable.PSEdition -eq 'Core') -and (
        $PSVersionTable.PSVersion.Major -gt 7 -or
        ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -ge 4)
    )
    if (-not $isSupportedPs) {
        return $false
    }

    if (Get-Module -Name PwshSpectreConsole) {
        return $true
    }

    if (-not $Force -and $script:WingetBatchSpectreChecked) {
        return $false
    }
    $script:WingetBatchSpectreChecked = $true

    $candidates = @()
    try {
        $candidates = @(Get-Module -ListAvailable -Name PwshSpectreConsole -ErrorAction SilentlyContinue | Sort-Object Version -Descending)
    } catch { }
    if ($candidates.Count -eq 0) {
        return $false
    }

    # Enable UTF-8 before Spectre initializes AnsiConsole.Profile so Unicode rendering works
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    try { $global:OutputEncoding = $utf8 } catch { }
    try { [Console]::InputEncoding = $utf8 } catch { }
    try { [Console]::OutputEncoding = $utf8 } catch { }

    # Guard against environments where the host ignores encoding changes (e.g. redirected/ISE)
    $hadIgnore = Test-Path 'env:IgnoreSpectreEncoding'
    $prevIgnore = $env:IgnoreSpectreEncoding
    try {
        if (-not $hadIgnore) {
            $env:IgnoreSpectreEncoding = 'True'
        }
        foreach ($candidate in $candidates) {
            try {
                $target = if ($candidate.Path) { $candidate.Path } else { 'PwshSpectreConsole' }
                Import-Module -Name $target -ErrorAction Stop
                break
            }
            catch {
                # Fall through to next installed copy or console fallback
            }
        }
    }
    finally {
        if (-not $hadIgnore) {
            Remove-Item 'env:IgnoreSpectreEncoding' -ErrorAction SilentlyContinue
        }
        else {
            $env:IgnoreSpectreEncoding = $prevIgnore
        }
    }

    return [bool](Get-Module -Name PwshSpectreConsole)
}
