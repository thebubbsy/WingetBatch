function New-WingetBatchGitHubToken {
    <#
    .SYNOPSIS
        Interactive helper to create and save a GitHub Personal Access Token.

    .DESCRIPTION
        Opens GitHub token creation page and guides you through the process.
        Automatically saves the token once you paste it.

    .EXAMPLE
        New-WingetBatchGitHubToken
        Opens GitHub and helps you create a token.

    .LINK
        https://github.com/settings/tokens
    #>

    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "🔑 GitHub Token Setup Wizard" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "I'll help you create a GitHub token to avoid API rate limits." -ForegroundColor White
    Write-Host ""
    Write-Host "Benefits:" -ForegroundColor Cyan
    Write-Host "  • " -NoNewline -ForegroundColor DarkGray
    Write-Host "60 requests/hour" -NoNewline -ForegroundColor Red
    Write-Host " → " -NoNewline -ForegroundColor DarkGray
    Write-Host "5,000 requests/hour" -ForegroundColor Green
    Write-Host "  • No special permissions needed" -ForegroundColor DarkGray
    Write-Host "  • Free forever" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Press Enter to open GitHub in your browser..." -ForegroundColor Yellow
    $null = Read-Host

    # Open GitHub token creation page
    $tokenUrl = "https://github.com/settings/tokens/new?description=WingetBatch&scopes="
    Start-Process $tokenUrl

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "📋 Follow these steps on GitHub:" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. " -NoNewline -ForegroundColor Yellow
    Write-Host "The token is already named 'WingetBatch'" -ForegroundColor White
    Write-Host ""
    Write-Host "2. " -NoNewline -ForegroundColor Yellow
    Write-Host "Set expiration (or choose 'No expiration' for convenience)" -ForegroundColor White
    Write-Host ""
    Write-Host "3. " -NoNewline -ForegroundColor Yellow
    Write-Host "DON'T check any permission boxes - none needed!" -ForegroundColor White
    Write-Host ""
    Write-Host "4. " -NoNewline -ForegroundColor Yellow
    Write-Host "Click " -NoNewline -ForegroundColor White
    Write-Host "'Generate token' " -NoNewline -ForegroundColor Green
    Write-Host "at the bottom" -ForegroundColor White
    Write-Host ""
    Write-Host "5. " -NoNewline -ForegroundColor Yellow
    Write-Host "COPY the token (starts with 'ghp_')" -ForegroundColor White
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""

    # Prompt for token
    $secureInput = Read-Host "Paste your token here" -AsSecureString
    $token = [System.Net.NetworkCredential]::new("", $secureInput).Password

    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Host ""
        Write-Host "❌ No token provided. Setup cancelled." -ForegroundColor Red
        Write-Host "   Run this command again when you have your token." -ForegroundColor DarkGray
        return
    }

    # Validate token format
    if ($token -notmatch '^ghp_[a-zA-Z0-9]{36}$' -and $token -notmatch '^github_pat_[a-zA-Z0-9_]+$') {
        Write-Host ""
        Write-Host "⚠️  Warning: Token format doesn't look right." -ForegroundColor Yellow
        Write-Host "   Expected format: ghp_xxxxxxxxxxxx or github_pat_xxxxxxxxxxxx" -ForegroundColor DarkGray
        Write-Host ""
        $continue = Read-Host "Continue anyway? (y/n)"
        if ($continue -ne 'y') {
            Write-Host "Setup cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Test the token
    Write-Host ""
    Write-Host "Testing token..." -ForegroundColor Cyan
    try {
        $testUrl = "https://api.github.com/user"
        $response = Invoke-RestMethod -Uri $testUrl -Headers @{
            'Authorization' = "Bearer $token"
            'User-Agent' = 'PowerShell-WingetBatch'
        } -ErrorAction Stop

        Write-Host "✓ Token is valid!" -ForegroundColor Green
        Write-Host "  Authenticated as: " -NoNewline -ForegroundColor DarkGray
        Write-Host $response.login -ForegroundColor White
    }
    catch {
        Write-Host "❌ Token test failed!" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host ""
        $continue = Read-Host "Save token anyway? (y/n)"
        if ($continue -ne 'y') {
            Write-Host "Setup cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Save token
    Set-WingetBatchGitHubToken -Token $token

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "✓ Setup Complete!" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now use all WingetBatch commands without rate limits!" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Try: " -NoNewline -ForegroundColor DarkGray
    Write-Host "Get-WingetNewPackages -Days 30" -ForegroundColor Yellow
    Write-Host ""
}
