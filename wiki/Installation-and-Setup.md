# Installation and Setup

This guide covers installing WingetBatch and configuring it for first use.

---

## Installation

### From PowerShell Gallery (Recommended)

```powershell
# Install the module for the current user
Install-Module -Name WingetBatch -Scope CurrentUser

# Import the module into your session
Import-Module WingetBatch
```

### Update to Latest Version

```powershell
# Update using the built-in updater
Update-WingetBatch

# Or manually via PowerShell Gallery
Update-Module -Name WingetBatch
```

### Standalone Script

For environments where module installation isn't practical, a standalone script is available:

```powershell
# Download and execute the standalone version
# See: WingetBatch_Standalone.ps1 in the repository
```

---

## First-Time Setup

### 1. GitHub Authentication (Recommended)

GitHub authentication unlocks the full potential of the Package Discovery feature by boosting API rate limits from 60 to 5,000 requests per hour.

```powershell
# Interactive OAuth flow (opens browser)
New-WingetBatchGitHubToken
```

Alternatively, set a Personal Access Token manually:

```powershell
# Set a GitHub PAT directly
Set-WingetBatchGitHubToken -Token "ghp_xxxxxxxxxxxxxxxxx"
```

> **Note:** Tokens are stored AES-encrypted via PowerShell's SecureString serialization, bound to your Windows user account.

### 2. Enable Update Notifications

Activate background monitoring to receive elegant notifications when package updates are available:

```powershell
# Enable with default interval
Enable-WingetUpdateNotifications

# Enable with a custom 4-hour check interval
Enable-WingetUpdateNotifications -Interval 4
```

After enabling, restart your terminal to see notifications in action.

### 3. Verify Installation

```powershell
# Check that all commands are available
Get-Command -Module WingetBatch

# Run the diagnostic tool
Repair-WingetBatchManager
```

---

## Dependencies

WingetBatch installs `Microsoft.WinGet.Client` automatically and integrates with optional modules when available:

| Module | Requirement | Purpose |
|:---|:---|:---|
| `Microsoft.WinGet.Client` | Required | COM API access for package operations |
| `PwshSpectreConsole` | Optional (PowerShell 7.4+) | Rich interactive terminal UI (falls back to numbered console selection on 5.1) |

---

## PowerShell Profile Integration

For the best experience, add WingetBatch to your PowerShell profile:

```powershell
# Open your profile in an editor
notepad $PROFILE

# Add this line:
Import-Module WingetBatch
```

This ensures update notifications display immediately when you open a new terminal session.

---

## Supported Environments

| Environment | Support Level |
|:---|:---|
| PowerShell 7.4+ (pwsh) | Full support (uses `PwshSpectreConsole` when installed, or built-in console fallback) |
| Windows PowerShell 5.1 | Full support with built-in interactive console selection (ideal for bootstrapping `pwsh` on fresh Windows installs) |
| Windows Terminal | Optimal experience |
| VS Code Integrated Terminal | Supported |
| ConEmu / Cmder | Supported |
