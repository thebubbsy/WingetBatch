# Command Reference

Complete reference for all WingetBatch public commands.

---

## Deployment Commands

### Install-WingetAll

Batch install packages from search results with interactive selection.

```powershell
Install-WingetAll [-SearchTerms] <string[]> [-MatchOption <string>] [-Silent] [-WhatIf]
    [-Mode <string>] [-Scope <string>] [-Architecture <string>] [-Override <string>]
    [-Location <string>] [-Force] [-SkipDependencies] [-AllowHashMismatch]
    [-IWantToLiterallyInstallAllFuckingResults] [-Id <string>] [-LimitResult <int>]
```

| Parameter | Description |
|:---|:---|
| `-SearchTerms` | One or more search terms (supports multi-word AND filtering) |
| `-MatchOption` | COM SearchMatchOption override (default: ContainsCaseInsensitive) |
| `-Silent` | Suppress installer UI |
| `-WhatIf` | Preview without installing |
| `-Mode` | Installation mode (Silent, Interactive) |
| `-Scope` | Install scope (User, Machine) |
| `-Architecture` | Target architecture (X64, X86, Arm64) |
| `-Override` | Override installer arguments |
| `-Location` | Custom install location |
| `-Force` | Force reinstall |
| `-SkipDependencies` | Skip package dependencies |
| `-AllowHashMismatch` | Allow installer hash mismatch |
| `-Id` | Specify exact package ID(s) instead of wildcard search |
| `-LimitResult` | Max results to return (default: 100) |
| `-IWantToLiterallyInstallAllFuckingResults` | Bypass all prompts, install everything matched |

**Examples:**
```powershell
# Interactive search and install
Install-WingetAll "nodejs"

# Silent install with machine scope
Install-WingetAll "python" -Silent -Scope Machine -Architecture X64

# Install by exact ID
Install-WingetAll -Id "Git.Git" -Silent
```

---

### Invoke-WinGetBatch

Idempotent, manifest-driven package deployments using native COM APIs.

```powershell
Invoke-WinGetBatch [-Path] <string> [-ThrottleLimit <int>] [-Silent] [-WhatIf]
```

| Parameter | Description |
|:---|:---|
| `-Path` | Path to JSON or YAML manifest file |
| `-ThrottleLimit` | Max parallel downloads (default: 4) |
| `-Silent` | Suppress all installer UI |
| `-WhatIf` | Preview deployment without executing |

**Example Manifest (YAML):**
```yaml
packages:
  - id: Git.Git
    version: latest
  - id: Python.Python.3.11
    version: 3.11.5
```

---

## Discovery Commands

### Get-WingetNewPackages

Discover truly new packages added to the winget ecosystem via GitHub API.

```powershell
Get-WingetNewPackages [-Hours <int>] [-Days <int>] [-GitHubToken <string>]
    [-ExcludeTerm <string[]>] [-IWantToLiterallyInstallAllFuckingResults]
    [-ExportHtml] [-Mode <string>] [-Scope <string>] [-Architecture <string>]
    [-Override <string>] [-Location <string>] [-ForceInstall] [-SkipDependencies]
    [-AllowHashMismatch]
```

| Parameter | Description |
|:---|:---|
| `-Hours` | Look-back window in hours |
| `-Days` | Look-back window in days |
| `-GitHubToken` | Override stored token for this session |
| `-ExcludeTerm` | Exclude packages matching these terms |
| `-ExportHtml` | Generate an HTML report |
| `-IWantToLiterallyInstallAllFuckingResults` | Auto-install all discovered packages |

**Examples:**
```powershell
# Find packages from the last 3 days
Get-WingetNewPackages -Days 3

# Exclude Microsoft packages and export report
Get-WingetNewPackages -Days 30 -ExcludeTerm "Microsoft" -ExportHtml
```

---

## Maintenance Commands

### Get-WingetUpdates

Check for and install available package updates.

```powershell
Get-WingetUpdates [-Force] [-IWantToLiterallyUpdateAllFuckingResults]
    [-ExportHtml] [-Mode <string>] [-Scope <string>] [-Architecture <string>]
    [-Override <string>] [-Location <string>] [-ForceInstall] [-SkipDependencies]
    [-AllowHashMismatch]
```

| Parameter | Description |
|:---|:---|
| `-Force` | Bypass 30-minute cache, force fresh check |
| `-IWantToLiterallyUpdateAllFuckingResults` | Auto-update all packages without prompting |
| `-ExportHtml` | Generate an HTML report of available updates |

**Examples:**
```powershell
# Interactive update check
Get-WingetUpdates

# Force fresh check and auto-update everything
Get-WingetUpdates -Force -IWantToLiterallyUpdateAllFuckingResults
```

---

### Remove-WingetRecent

Uninstall recently installed packages by date range.

```powershell
Remove-WingetRecent [-Days <int>]
```

| Parameter | Description |
|:---|:---|
| `-Days` | Look-back window in days (e.g., 7 for last week) |

---

### Invoke-WingetBatchCleanup

Clean up cache and temporary files.

```powershell
Invoke-WingetBatchCleanup
```

---

### Repair-WingetBatchManager

Diagnose and repair common winget issues.

```powershell
Repair-WingetBatchManager
```

Checks performed:
- winget.exe PATH availability
- Microsoft.WinGet.Client module status
- COM API health
- Auto-repair via App Installer re-registration

---

## Reporting Commands

### Export-WingetHtmlReport

Generate professional standalone HTML reports from package data.

```powershell
Export-WingetHtmlReport [-Data] <array> [-ReportTitle <string>] [-FilePath <string>]
```

| Parameter | Description |
|:---|:---|
| `-Data` | Array of objects to include in the report |
| `-ReportTitle` | Title for the report |
| `-FilePath` | Output file path (.html) |

**Example:**
```powershell
$data = @(@{Name="App1"; Version="1.0"}, @{Name="App2"; Version="2.0"})
Export-WingetHtmlReport -Data $data -ReportTitle "Custom Audit" -FilePath ".\audit.html"
```

---

## Automation Commands

### Enable-WingetUpdateNotifications

Activate background update monitoring with profile integration.

```powershell
Enable-WingetUpdateNotifications [-Interval <int>]
```

| Parameter | Description |
|:---|:---|
| `-Interval` | Check interval in hours (default: startup) |

---

### Disable-WingetUpdateNotifications

Deactivate background update monitoring.

```powershell
Disable-WingetUpdateNotifications
```

---

### Start-WingetUpdateCheck

Manually trigger an update check (used internally by the notification system).

```powershell
Start-WingetUpdateCheck
```

---

## Authentication Commands

### New-WingetBatchGitHubToken

Interactive GitHub OAuth flow to create and store an API token.

```powershell
New-WingetBatchGitHubToken
```

Opens your default browser for GitHub authentication. The resulting token is stored encrypted.

---

### Set-WingetBatchGitHubToken

Manually set or remove a GitHub API token.

```powershell
Set-WingetBatchGitHubToken [-Token <string>] [-Remove]
```

| Parameter | Description |
|:---|:---|
| `-Token` | GitHub Personal Access Token to store |
| `-Remove` | Remove the stored token |

---

## Configuration Commands

### Get-WingetBatchConfig

View current module configuration.

```powershell
Get-WingetBatchConfig
```

---

### Set-WingetBatchConfig

Set module preferences.

```powershell
Set-WingetBatchConfig [-Key <string>] [-Value <object>]
```

---

### Export-WingetBatchConfig

Backup local configuration to a file.

```powershell
Export-WingetBatchConfig [-Path <string>]
```

---

### Import-WingetBatchConfig

Restore configuration from a backup file.

```powershell
Import-WingetBatchConfig [-Path <string>]
```

---

### Update-WingetBatch

Update the WingetBatch module to the latest version.

```powershell
Update-WingetBatch
```
