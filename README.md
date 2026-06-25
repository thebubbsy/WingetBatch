# WingetBatch PowerShell Module

Batch installation utilities and reporting tools for Windows Package Manager (winget). Search for packages, install results, and generate professional reports with a single command.

## Features

### 🚀 Batch Installation
- **Intelligent Search**: Search for packages and install all matching results in one go.
- **Interactive UI**: Uses PwshSpectreConsole for a modern, fluid interactive package selection experience.
- **Smart Filtering**: Supports complex multi-word searches with logical AND filtering.
- **Progress Visibility**: Clear, visual feedback during the entire installation lifecycle.

### 📊 HTML Reporting (NEW v2.2.0)
- **Visual Insights**: Generate professional, stand-alone HTML reports for newly discovered packages or available updates.
- **Interactive Reports**: Reports include clean layouts and direct package identifiers.
- **Easy Export**: Use the `-ExportHtml` switch on supported commands to generate a shareable audit trail.

### 🔔 Smart Update Notifications
- **Background Intelligence**: Automatically monitors your system for winget package updates in the background.
- **Zero-Latency Profile Integration**: Displays elegant notifications instantly when you open your terminal.
- **Precision Control**: Configurable check intervals (startup, hourly, or custom) to balance freshness and performance.
- **Selective Updating**: Interactively choose exactly which packages to update.

### 📦 New Package Discovery
- **Forensic Discovery**: Directly queries the `winget-pkgs` GitHub repository to find truly new packages, not just version bumps.
- **Historical Analysis**: Look back hours, days, or weeks to see what has been added to the ecosystem.
- **Massive Scale**: Fetches all commits without artificial limits, powered by GitHub API integration.

### 🔑 Secure Authentication
- **Enterprise Rate Limits**: Integrated GitHub authentication boosts API limits from 60 to 5,000 requests per hour.
- **Zero-Config Usage**: Automatically leverages stored credentials across all modules.
- **Hardware-Bound Security**: Tokens are encrypted using PowerShell's secure storage, locked to your Windows user account.

## Installation

```powershell
# Install from PowerShell Gallery
Install-Module -Name WingetBatch -Scope CurrentUser

# Import the module
Import-Module WingetBatch
```

## Quick Start

### 1. Set up GitHub Authentication (Recommended)
```powershell
# Authenticate interactively (opens browser)
New-WingetBatchGitHubToken

# This unlocks the full potential of New Package Discovery with 5,000 req/hr
```

### 2. Enable Advanced Notifications
```powershell
# Activate background monitoring
Enable-WingetUpdateNotifications

# Restart your terminal to see the logic in action
```

### 3. Generate an HTML Report
```powershell
# Find new packages from the last 3 days and export to HTML
Get-WingetNewPackages -Days 3 -ExportHtml
```

## Command Reference

| Command | Category | Description |
|:---|:---|:---|
| `Install-WingetAll` | **Deployment** | Batch install packages from search results |
| `Get-WingetNewPackages` | **Discovery** | Find truly new packages added to winget |
| `Get-WingetUpdates` | **Maintenance** | Check and install available updates |
| `Export-WingetHtmlReport` | **Reporting** | Generate HTML audit reports from package data |
| `Enable-WingetUpdateNotifications` | **Automation** | Activate background update monitoring |
| `Disable-WingetUpdateNotifications` | **Automation** | Deactivate update monitoring |
| `Set-WingetBatchGitHubToken` | **Auth** | Set or remove GitHub API token |
| `New-WingetBatchGitHubToken` | **Auth** | Interactive GitHub OAuth flow |
| `Invoke-WingetBatchCleanup` | **Maintenance** | Clean up cache and temporary files |
| `Remove-WingetRecent` | **Maintenance** | Clear local history of installed packages |
| `Repair-WingetBatchManager` | **Diagnostics** | Diagnose and repair common winget issues |
| `Invoke-WinGetBatch` | **Deployment** | Idempotent manifest-driven package deployments |
| `Export-WingetBatchConfig` | **System** | Backup local configuration |
| `Import-WingetBatchConfig` | **System** | Restore configuration from backup |

## Usage Examples

### 📦 Precision Deployment
```powershell
# Install nodejs silently
Install-WingetAll "nodejs" -Silent
```

### 🆕 Advanced Discovery
```powershell
# Find packages from the last 30 days, excluding Microsoft spam
Get-WingetNewPackages -Days 30 -ExcludeTerm "Microsoft" -ExportHtml
```

### 🛠️ Maintenance
```powershell
# Force a fresh update check bypassing the 30-min cache
Get-WingetUpdates -Force
```

## Configuration & Storage

- **Config Location**: `~\.wingetbatch\config.json`
- **Secure Credentials**: `~\.wingetbatch\github_token.clixml` (AES encrypted)
- **Performance Cache**: `~\.wingetbatch\update_cache.json` (30 min TTL)

## Requirements

- **Windows Package Manager** (winget)
- **PowerShell 5.1** or **PowerShell 7+** (Recommended)
- **Microsoft.WinGet.Client** module (Auto-installed as a dependency)
- **PwshSpectreConsole** module (Auto-installed if missing)

## Next-Generation Architecture

We are actively designing a next-generation architecture to transition `wingetbatch` from a CLI wrapper to an enterprise-grade package deployment tool. Key pillars include:
* **COM API Integration (`Microsoft.WinGet.Client`)** to eliminate stdout parsing.
* **Split-Phase Concurrency (RunspacePools)** for parallel downloading with serialized installation.
* **Declarative State Management** for idempotent deployments.

For a detailed breakdown of the roadmap and execution logic, view our [Next-Generation Architecture Roadmap](docs/architecture_nextgen.md).

## Credits & Attribution

**WingetBatch** is architected and maintained exclusively by **Matthew Bubb**.

## Version History

- **2.5.0** (Current) - COM API Migration: Replaced all winget.exe CLI text-parsing with Microsoft.WinGet.Client COM API. Added Repair-WingetBatchManager.
- **2.4.7** - Performance and stability improvements.
- **2.2.1** - Resolved HTML report parameter binding issues and improved module loading robustness.
- **2.2.0** - Added professional HTML reporting engine (`-ExportHtml`).
- **2.1.0** - Enhanced cache management and high-volume GitHub commit fetching.
- **2.0.0** - Major overhaul: Added update notifications, discovery engine, and GitHub Auth.
- **1.0.0** - Initial release: Batch installation core.

## License

MIT License - See LICENSE file for details.
