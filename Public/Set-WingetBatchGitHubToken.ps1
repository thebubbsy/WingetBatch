function Set-WingetBatchGitHubToken {
    <#
    .SYNOPSIS
        Set or update the GitHub Personal Access Token for API authentication.

    .DESCRIPTION
        Stores a GitHub token securely to avoid API rate limits when checking for new packages.
        Without a token, you're limited to 60 requests/hour. With a token, you get 5,000 requests/hour.
        The token is stored securely using PowerShell's Export-Clixml with SecureString.

        For an interactive wizard, use New-WingetBatchGitHubToken instead.

    .PARAMETER Token
        Your GitHub Personal Access Token. Create one at https://github.com/settings/tokens
        No special permissions are required.

    .PARAMETER Remove
        Remove the stored GitHub token.

    .EXAMPLE
        Set-WingetBatchGitHubToken -Token "ghp_xxxxxxxxxxxx"
        Stores your GitHub token for future use.

    .EXAMPLE
        Set-WingetBatchGitHubToken -Remove
        Removes the stored GitHub token.

    .EXAMPLE
        New-WingetBatchGitHubToken
        Use the interactive wizard instead.

    .LINK
        https://github.com/settings/tokens
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Set')]
        [string]$Token,

        [Parameter(Mandatory=$true, ParameterSetName='Remove')]
        [switch]$Remove
    )

    $configDir = Get-WingetBatchConfigDir
    $tokenFile = Join-Path $configDir "github_token.clixml"
    $legacyFile = Join-Path $configDir "github_token.txt"

    if ($Remove) {
        $removed = $false
        if (Test-Path $tokenFile) {
            Remove-Item $tokenFile -Force
            $removed = $true
        }
        if (Test-Path $legacyFile) {
            Remove-Item $legacyFile -Force
            $removed = $true
        }

        if ($removed) {
            Write-Host "✓ GitHub token removed successfully" -ForegroundColor Green
        }
        else {
            Write-Host "No GitHub token found to remove" -ForegroundColor Yellow
        }
        return
    }

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Store token securely
    try {
        $SecureToken = $Token | ConvertTo-SecureString -AsPlainText -Force
        $SecureToken | Export-Clixml -Path $tokenFile

        # Remove legacy plaintext file if it exists
        if (Test-Path $legacyFile) {
            Remove-Item $legacyFile -Force
        }

        Write-Host "✓ GitHub token saved securely!" -ForegroundColor Green
        Write-Host "  Location: $tokenFile" -ForegroundColor DarkGray
        Write-Host "  The token will now be used automatically for API requests." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  ℹ Security Note:" -ForegroundColor Yellow
        Write-Host "  • Token stored securely using PowerShell encryption (bound to your user account)" -ForegroundColor DarkGray
        Write-Host "  • Only increases API rate limits - cannot modify repositories or access private data" -ForegroundColor DarkGray
        Write-Host "  • Revoke anytime at: https://github.com/settings/tokens" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "❌ Failed to save token securely: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}
