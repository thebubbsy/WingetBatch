# WingetBatch PowerShell Module

Batch installation utilities and reporting tools for Windows Package Manager (winget). Search for packages, install results, and generate professional reports with a single command.

## Features

### 🚀 Batch Installation
- **Intelligent Search**: Search for packages and install all matching results in one go.
- **Interactive UI**: Uses PwshSpectreConsole for a modern, fluid interactive package selection experience.
- **Smart Filtering**: Supports complex multi-word searches with logical AND filtering.
- **Progress Visibility**: Clear, visual feedback with [N/M] progress counters during the entire installation lifecycle.

### 🖥️ Machine-as-Code (NEW v2.7.0)
- **State Snapshots**: Export your entire machine's package set to a portable JSON/YAML manifest.
- **Drift Detection**: Compare any machine against a golden baseline and see exactly what's missing, outdated, or extraneous.
- **Auto-Reconciliation**: One command to install missing, update outdated, and optionally remove extraneous packages.
- **Golden Machine Replication**: Snapshot a configured machine, then replicate its package set onto any other Windows machine.

### 📊 Live Dashboard (NEW v2.7.0)
- **Real-Time Monitoring**: `Watch-WingetPackages` displays a live-updating terminal dashboard (htop-style).
- **System Health**: Winget engine status, source index freshness, GitHub auth state at a glance.
- **Package Statistics**: Total installed, pending updates, recent installs, source breakdown.

### 🔍 Package Intelligence (NEW v2.7.0)
- **Rich Package Info**: `Get-WingetPackageInfo` shows brew-info-style details with GitHub manifest data.
- **Duplicate Detection**: `Find-WingetDuplicate` finds multi-source installs, name collisions, and version clusters.
- **Installation History**: `Get-WingetHistory` displays a chronological timeline from registry and winget logs.
- **Tab Completion**: Intelligent argument completers for package IDs across all commands.

### 📊 HTML Reporting
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

> [!WARNING]
> **The Power of `-IWantToLiterallyInstallAllFuckingResults`**
> 
> This parameter is insanely powerful and bypasses all interactive prompts and safeguards to automatically install every single matched package. When paired with broad searches (e.g., searching for "Microsoft", or using `Get-WingetNewPackages -Days 30`), you can easily lead yourself down a path where you automatically queue and install over 200 applications without warning. Use this parameter with extreme caution!

## Command Reference

| Command | Category | Description | Parameters |
|:---|:---|:---|:---|
| `Install-WingetAll` | **Deployment** | Batch install packages from search results | `-SearchTerms`, `-MatchOption`, `-Silent`, `-WhatIf`, `-Mode`, `-Scope`, `-Architecture`, `-Override`, `-Location`, `-Force`, `-SkipDependencies`, `-AllowHashMismatch`, `-IWantToLiterallyInstallAllFuckingResults` |
| `Invoke-WinGetBatch` | **Deployment** | Idempotent manifest-driven package deployments | `-Path`, `-ThrottleLimit`, `-Silent`, `-WhatIf` |
| `Get-WingetMachineState` | **State** | Snapshot, compare, and reconcile machine package state | `-Export`, `-Compare`, `-Reconcile`, `-Path`, `-Format`, `-IncludeVersions`, `-RemoveExtraneous`, `-Source` |
| `Get-WingetNewPackages` | **Discovery** | Find truly new packages added to winget | `-Hours`, `-Days`, `-GitHubToken`, `-ExcludeTerm`, `-IWantToLiterallyInstallAllFuckingResults`, `-ExportHtml`, `-Mode`, `-Scope`, `-Architecture`, `-Override`, `-Location`, `-ForceInstall`, `-SkipDependencies`, `-AllowHashMismatch` |
| `Get-WingetPackageInfo` | **Discovery** | Rich package information display (brew-info style) | `-Id`, `-Query`, `-ShowManifest`, `-ShowVersions` |
| `Get-WingetUpdates` | **Maintenance** | Check and install available updates | `-Force`, `-IWantToLiterallyUpdateAllFuckingResults`, `-ExportHtml`, `-Mode`, `-Scope`, `-Architecture`, `-Override`, `-Location`, `-ForceInstall`, `-SkipDependencies`, `-AllowHashMismatch` |
| `Get-WingetHistory` | **Maintenance** | Installation history timeline | `-Days`, `-All`, `-Search`, `-ExportHtml`, `-ExportJson` |
| `Find-WingetDuplicate` | **Maintenance** | Detect duplicate and redundant packages | `-IncludeVersions`, `-ExportHtml` |
| `Watch-WingetPackages` | **Monitoring** | Live terminal dashboard for package state | `-RefreshInterval`, `-Once` |
| `Export-WingetHtmlReport` | **Reporting** | Generate HTML audit reports from package data | `-Data`, `-ReportTitle`, `-FilePath` |
| `Enable-WingetUpdateNotifications` | **Automation** | Activate background update monitoring | `-Interval` |
| `Disable-WingetUpdateNotifications` | **Automation** | Deactivate update monitoring | *None* |
| `Set-WingetBatchGitHubToken` | **Auth** | Set or remove GitHub API token | `-Token`, `-Remove` |
| `New-WingetBatchGitHubToken` | **Auth** | Interactive GitHub OAuth flow | *None* |
| `Invoke-WingetBatchCleanup` | **Maintenance** | Clean up cache and temporary files | *None* |
| `Remove-WingetRecent` | **Maintenance** | Clear local history of installed packages | `-Days` |
| `Repair-WingetBatchManager` | **Diagnostics** | Diagnose and repair common winget issues | *None* |
| `Export-WingetBatchConfig` | **System** | Backup local configuration | `-Path` |
| `Import-WingetBatchConfig` | **System** | Restore configuration from backup | `-Path` |

## Usage Examples

### 📦 Precision Deployment
```powershell
# Install nodejs silently
Install-WingetAll "nodejs" -Silent

# Use advanced COM parameters to install Python specifically to Machine scope with custom architecture and location
Install-WingetAll "python" -Scope Machine -Architecture X64 -Location "C:\Python" -Mode Silent

# Deploy packages from a manifest file with custom throttling
Invoke-WinGetBatch -Path ".\work-apps.yaml" -ThrottleLimit 6 -Silent -SkipDependencies -AllowHashMismatch
```

### 🆕 Advanced Discovery
```powershell
# Find packages from the last 30 days, excluding Microsoft spam
Get-WingetNewPackages -Days 30 -ExcludeTerm "Microsoft" -ExportHtml
```

### 🛠️ Maintenance & Updates
```powershell
# Force a fresh update check bypassing the 30-min cache
Get-WingetUpdates -Force

# Auto-update everything without prompting
Get-WingetUpdates -IWantToLiterallyUpdateAllFuckingResults

# Clear recently installed packages history older than 5 days
Remove-WingetRecent -Days 5

# Clean up temporary files and cache
Invoke-WingetBatchCleanup

# Diagnose and repair Winget Batch Manager issues
Repair-WingetBatchManager
```

### ⚙️ Automation & Configuration
```powershell
# Enable background update notifications every 4 hours
Enable-WingetUpdateNotifications -Interval 4

# Disable background update notifications
Disable-WingetUpdateNotifications

# Export current WingetBatch configuration to a file
Export-WingetBatchConfig -Path ".\wingetbatch-backup.json"

# Restore WingetBatch configuration from a backup
Import-WingetBatchConfig -Path ".\wingetbatch-backup.json"
```

### 🖥️ Machine-as-Code (NEW)
```powershell
# Snapshot this machine's packages to a portable manifest
Get-WingetMachineState -Export -Path ".\golden-machine.json"

# Export with exact version pins in YAML
Get-WingetMachineState -Export -Path ".\state.yaml" -Format YAML -IncludeVersions

# Compare current machine against golden baseline (drift detection)
Get-WingetMachineState -Compare -Path ".\golden-machine.json"

# Reconcile: install missing + update outdated packages
Get-WingetMachineState -Reconcile -Path ".\golden-machine.json"

# Full reconciliation: also remove packages not in the manifest
Get-WingetMachineState -Reconcile -Path ".\golden-machine.json" -RemoveExtraneous
```

### 🔍 Package Intelligence (NEW)
```powershell
# Rich package info (brew-info style)
Get-WingetPackageInfo -Id "Git.Git"

# Search and explore packages
Get-WingetPackageInfo -Query "visual studio code" -ShowVersions

# Live terminal dashboard (htop-style monitoring)
Watch-WingetPackages
Watch-WingetPackages -RefreshInterval 60 -Once

# Find duplicate/redundant packages
Find-WingetDuplicate -IncludeVersions

# Installation history timeline (last 7 days)
Get-WingetHistory -Days 7

# Full history with search filter
Get-WingetHistory -All -Search "python" -ExportHtml
```

### 🔐 Authentication & Reporting
```powershell
# Interactively authenticate with GitHub via OAuth
New-WingetBatchGitHubToken

# Manually set a GitHub Personal Access Token
Set-WingetBatchGitHubToken -Token "ghp_xxxxxxxxxxxxxxxxx"

# Remove GitHub Token
Set-WingetBatchGitHubToken -Remove

# Export custom data to a stylized HTML report
$data = @(@{Name="App1"; Version="1.0"}, @{Name="App2"; Version="2.0"})
Export-WingetHtmlReport -Data $data -ReportTitle "Custom Audit" -FilePath ".\audit.html"
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

- **2.7.0** (Current) - Machine-as-Code & Developer Experience: Get-WingetMachineState (snapshot/compare/reconcile), Get-WingetPackageInfo, Get-WingetHistory, Watch-WingetPackages (live dashboard), Find-WingetDuplicate, tab-completion, security fixes (Invoke-Expression elimination), deduplication bug fix.
- **2.5.0** - COM API Migration: Replaced all winget.exe CLI text-parsing with Microsoft.WinGet.Client COM API. Added Repair-WingetBatchManager.
- **2.4.7** - Performance and stability improvements.
- **2.2.1** - Resolved HTML report parameter binding issues and improved module loading robustness.
- **2.2.0** - Added professional HTML reporting engine (`-ExportHtml`).
- **2.1.0** - Enhanced cache management and high-volume GitHub commit fetching.
- **2.0.0** - Major overhaul: Added update notifications, discovery engine, and GitHub Auth.
- **1.0.0** - Initial release: Batch installation core.

## License

MIT License - See LICENSE file for details.
