function Get-WingetBatchGitHubToken {
    <#
    .SYNOPSIS
        Retrieve the stored GitHub token.

    .DESCRIPTION
        Internal function to get the stored GitHub token for API authentication.
        Handles both secure CliXml and legacy plaintext formats with automatic migration.

    .OUTPUTS
        String - The GitHub token if found, otherwise $null
    #>

    [CmdletBinding()]
    param()

    $configDir = Get-WingetBatchConfigDir
    $tokenFile = Join-Path $configDir "github_token.clixml"
    $legacyFile = Join-Path $configDir "github_token.txt"

    # 1. Try to load from secure storage
    if (Test-Path $tokenFile) {
        try {
            $SecureToken = Import-Clixml -Path $tokenFile -ErrorAction Stop
            if ($SecureToken -is [System.Security.SecureString]) {
                return [System.Net.NetworkCredential]::new("", $SecureToken).Password
            }
        }
        catch {
            # If clixml is corrupted or not a SecureString, we'll try legacy as fallback
        }
    }

    # 2. Migration: Try legacy plaintext storage
    if (Test-Path $legacyFile) {
        try {
            $Token = (Get-Content $legacyFile -Raw).Trim()
            if (-not [string]::IsNullOrWhiteSpace($Token)) {
                # Silently migrate to secure format
                Set-WingetBatchGitHubToken -Token $Token | Out-Null
                return $Token
            }
        }
        catch {
            return $null
        }
    }

    return $null
}
