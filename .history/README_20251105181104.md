# WingetBatch PowerShell Module

Batch installation utilities for Windows Package Manager (winget). Search for packages and install all matching results with a single command.

## Features

### 🚀 Batch Installation
- **Batch Installation**: Search for packages and install all results with a single command
- **Interactive Selection**: Uses PwshSpectreConsole for modern, interactive package selection
- **Smart Filtering**: Supports multi-word searches with AND logic
- **Progress Tracking**: Visual feedback during installation process

### 🔔 Update Notifications
- **Background Monitoring**: Automatically checks for winget package updates
- **Profile Integration**: Displays notifications when you open your terminal
- **Configurable Intervals**: Check on startup, hourly, or set custom intervals
- **Interactive Updates**: Select which packages to update with a visual interface

### 📦 New Package Discovery
- **GitHub Integration**: Discover newly added packages from winget-pkgs repository
- **Date Filtering**: Search for packages added in the last N days
- **Smart Detection**: Filters out version updates to show only truly new packages
- **Direct Installation**: Select and install new packages interactively

### 🔑 GitHub Authentication
- **Rate Limit Management**: Store GitHub token to get 5,000 API requests/hour
- **Automatic Token Usage**: Stored tokens are used automatically across all features
- **Secure Storage**: Tokens stored locally in your user profile

## Installation

```powershell
# Clone or download this module to your PowerShell modules directory
# Default location: ~\Documents\PowerShell\Modules\WingetBatch\

# Or copy the files to:
$env:USERPROFILE\Documents\PowerShell\Modules\WingetBatch\
```

## Quick Start

### 1. Set up GitHub Authentication (Optional but Recommended)

```powershell
# Create a token at: https://github.com/settings/tokens (no special permissions needed)
Set-WingetBatchGitHubToken -Token "ghp_your_token_here"
```

### 2. Enable Update Notifications

```powershell
# Enable automatic update checks
Enable-WingetUpdateNotifications

# Restart your terminal, and you'll see update notifications like:
# 📦 5 winget package update(s) available
#    Run Get-WingetUpdates to view and install them
```

### 3. Check for Updates

```powershell
# View and install available updates interactively
Get-WingetUpdates
```

### 4. Discover New Packages

```powershell
# Find packages added to winget in the last 7 days
Get-WingetNewPackages

# Or search further back
Get-WingetNewPackages -Days 30
```

### 5. Batch Install Packages

```powershell
# Search and install packages
Install-WingetAll "python"
```

## Usage

### 📦 Package Installation

#### Basic Usage
Search for packages and install them interactively:
```powershell
Install-WingetAll "python"
```

#### Silent Installation
Skip the confirmation prompt:
```powershell
Install-WingetAll "nodejs" -Silent
```

#### WhatIf Mode
Preview what would be installed without actually installing:
```powershell
Install-WingetAll "python" -WhatIf
```

### 🔔 Update Management

#### Enable Notifications
```powershell
# Default: Check on startup and every 3 hours
Enable-WingetUpdateNotifications

# Check every 6 hours
Enable-WingetUpdateNotifications -Interval 6

# Only check on startup
Enable-WingetUpdateNotifications -Interval 0 -CheckOnStartup $true
```

#### Check for Updates
```powershell
# Interactive update selection
Get-WingetUpdates

# Force a fresh check (bypass cache)
Get-WingetUpdates -Force
```

#### Disable Notifications
```powershell
Disable-WingetUpdateNotifications
```

### 🆕 Discover New Packages

#### Find Recently Added Packages
```powershell
# Last 7 days (default)
Get-WingetNewPackages

# Last 30 days
Get-WingetNewPackages -Days 30

# With GitHub token for higher rate limits
Get-WingetNewPackages -Days 60 -GitHubToken "ghp_token"
```

### 🔑 GitHub Authentication

#### Set Token
```powershell
# Save your GitHub token (increases rate limit from 60 to 5,000 req/hour)
Set-WingetBatchGitHubToken -Token "ghp_xxxxxxxxxxxx"
```

#### Remove Token
```powershell
Set-WingetBatchGitHubToken -Remove
```

## Configuration

### Update Notification Settings

Configuration is stored in `~\.wingetbatch\config.json`:

```json
{
  "UpdateNotificationsEnabled": true,
  "CheckInterval": 3,
  "CheckOnStartup": true,
  "LastCheck": "2025-11-05T10:30:00Z"
}
```

### GitHub Token

Token is stored in `~\.wingetbatch\github_token.txt` (plain text - keep secure!)

### Cache Files

- `~\.wingetbatch\update_cache.json` - Cached update check results (30 min TTL)

## Requirements

- Windows Package Manager (winget)
- PowerShell 5.1 or later
- PwshSpectreConsole module (automatically installed if missing)
- GitHub Personal Access Token (optional, for higher API rate limits)

## Commands Reference

| Command | Description |
|---------|-------------|
| `Install-WingetAll` | Batch install packages from search results |
| `Get-WingetNewPackages` | Discover newly added packages from GitHub |
| `Get-WingetUpdates` | Check and install available updates |
| `Enable-WingetUpdateNotifications` | Enable automatic update notifications |
| `Disable-WingetUpdateNotifications` | Disable update notifications |
| `Set-WingetBatchGitHubToken` | Set or remove GitHub API token |

## Troubleshooting

### GitHub API Rate Limit

If you see rate limit errors:
1. Create a GitHub token at https://github.com/settings/tokens
2. Run `Set-WingetBatchGitHubToken -Token "your_token"`
3. The token will be used automatically for all API requests

### Update Notifications Not Showing

1. Check if notifications are enabled: `Enable-WingetUpdateNotifications`
2. Restart your terminal
3. Check config: `Get-Content ~/.wingetbatch/config.json`

### PwshSpectreConsole Not Available

The module will automatically attempt to install it. If it fails:
```powershell
Install-Module -Name PwshSpectreConsole -Scope CurrentUser -Force
```

## License

MIT License - See LICENSE file for details

## Author

Matthew Bubb - Created November 2025

## Version History

- **2.0.0** (Nov 2025) - Added update notifications, new package discovery, GitHub auth
- **1.0.0** (Nov 2025) - Initial release with batch installation
