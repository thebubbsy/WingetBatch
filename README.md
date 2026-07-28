# WingetBatch PowerShell Module

The ultimate Windows Package Manager power tool. 26 commands for batch deployment, AI-powered recommendations, machine-as-code state management, REST API server, fleet automation, live dashboards, dependency graphs, and scheduled maintenance — all from your terminal.

```powershell
Install-Module WingetBatch
```

## Features

### 🧠 AI Package Recommender (NEW v2.8.0)
- **Persona Matching**: Say "I'm a backend dev" and get a curated, scored install list.
- **Clone Personality**: Analyzes your installed packages and recommends what's missing using co-occurrence patterns.
- **10 Built-in Archetypes**: Backend Dev, Frontend Dev, Data Scientist, DevOps, Gamer, Game Dev, Security Researcher, Designer, Productivity, Student.
- **One-Key Install**: Pipe recommendations directly into interactive install.

### 🌐 REST API Server (NEW v2.8.0)
- **Remote Management**: Full HTTP API for package operations via [Pode](https://github.com/Badgerati/Pode).
- **12 Endpoints**: List, search, install, uninstall, update, state, history, stats, health.
- **Secured**: API key auth, per-IP rate limiting, request logging.
- **Self-Documenting**: `GET /` returns the full endpoint catalog.

### 🔧 Scheduled Maintenance (NEW v2.8.0)
- **Auto-Updates**: Register a Windows Scheduled Task for hands-free package maintenance.
- **Flexible Schedules**: Daily, Weekly, Monthly with configurable time and actions.
- **5 Actions**: UpdateAll, UpdateOutdated, CleanupTemp, AuditDrift, NotifyOnly.
- **Full Lifecycle**: `-Status`, `-RunNow`, `-Unregister` for complete control.

### 🕸️ Dependency Graphs (NEW v2.8.0)
- **Visualize Relationships**: See how packages depend on each other.
- **4 Output Formats**: Mermaid (GitHub), DOT (Graphviz), ASCII Tree, structured Object.
- **Circular Detection**: Finds and highlights dependency cycles.
- **Configurable Depth**: Traverse 1–10 levels deep.

### 🖥️ Machine-as-Code
- **State Snapshots**: Export your entire machine's package set to portable JSON/YAML.
- **Drift Detection**: Compare any machine against a golden baseline.
- **Auto-Reconciliation**: Install missing, update outdated, remove extraneous — one command.

### 📊 Live Dashboard
- **Real-Time Monitoring**: `Watch-WingetPackages` — htop-style terminal dashboard.
- **System Health**: Winget status, source freshness, GitHub auth, package stats at a glance.

### 🔍 Package Intelligence
- **Rich Info**: `Get-WingetPackageInfo` — brew-info-style details with GitHub manifest data.
- **Duplicate Detection**: Multi-source installs, name collisions, version clusters.
- **History Timeline**: Chronological install history from registry and winget logs.
- **Tab Completion**: Intelligent argument completers across all commands.

### 🚀 Batch Deployment
- **Intelligent Search**: Multi-word AND filtering with COM API.
- **Interactive UI**: PwshSpectreConsole multi-select experience.
- **Idempotent Manifests**: `Invoke-WinGetBatch` — declarative JSON/YAML deployments.
- **Split-Phase Concurrency**: Parallel downloads, serialized installs.

### 📦 Discovery & Updates
- **New Package Discovery**: Queries winget-pkgs GitHub repo for truly new packages.
- **Smart Update Checks**: Background monitoring with 30-min cache TTL.
- **HTML Reporting**: Professional standalone reports for audits.

### 🔑 Security
- **GitHub Auth**: 5,000 req/hr (vs 60 unauthenticated).
- **AES Encryption**: Tokens encrypted with Windows DPAPI.
- **No Invoke-Expression**: All execution uses safe argument arrays and COM API.

## Installation

```powershell
# From PowerShell Gallery
Install-Module -Name WingetBatch -Scope CurrentUser

# Import
Import-Module WingetBatch
```

## Quick Start

```powershell
# "I'm a backend developer" — get AI recommendations
Get-WingetRecommend -Persona "backend developer" -Install

# Clone this machine's personality onto a new PC
Get-WingetRecommend -ClonePersonality

# Start the REST API for remote management
Start-WingetServer -Port 8484

# Schedule weekly auto-updates at 3AM
Register-WingetMaintenance -Schedule Weekly -Time 03:00

# Snapshot this machine as a golden baseline
Get-WingetMachineState -Export -Path ".\golden.json"

# Live dashboard
Watch-WingetPackages
```

## Command Reference (26 Commands)

| Command | Category | Description |
|:---|:---|:---|
| `Get-WingetRecommend` | **AI** | Persona-based and personality-clone package recommendations |
| `Start-WingetServer` | **API** | REST API server for remote package management (Pode) |
| `Register-WingetMaintenance` | **Automation** | Scheduled maintenance tasks for auto-updates |
| `Get-WingetDependencyGraph` | **Visualization** | Package dependency graph (Mermaid/DOT/Tree) |
| `Get-WingetMachineState` | **State** | Snapshot, compare, reconcile machine state |
| `Watch-WingetPackages` | **Monitoring** | Live terminal dashboard (htop-style) |
| `Get-WingetPackageInfo` | **Discovery** | Rich brew-info-style package explorer |
| `Find-WingetDuplicate` | **Maintenance** | Detect duplicates and version clusters |
| `Get-WingetHistory` | **Maintenance** | Installation history timeline |
| `Install-WingetAll` | **Deployment** | Batch install from search results |
| `Invoke-WinGetBatch` | **Deployment** | Idempotent manifest-driven deployments |
| `Get-WingetNewPackages` | **Discovery** | Find truly new packages on winget |
| `Get-WingetUpdates` | **Maintenance** | Check and install available updates |
| `Enable-WingetUpdateNotifications` | **Automation** | Background update monitoring |
| `Disable-WingetUpdateNotifications` | **Automation** | Disable update monitoring |
| `Set-WingetBatchGitHubToken` | **Auth** | Set/remove GitHub API token |
| `New-WingetBatchGitHubToken` | **Auth** | Interactive GitHub OAuth flow |
| `Remove-WingetRecent` | **Maintenance** | Uninstall recently added packages |
| `Invoke-WingetBatchCleanup` | **Maintenance** | Clean cache and temp files |
| `Repair-WingetBatchManager` | **Diagnostics** | Diagnose and repair winget issues |
| `Export-WingetBatchConfig` | **System** | Backup configuration |
| `Import-WingetBatchConfig` | **System** | Restore configuration |
| `Set-WingetBatchConfig` | **System** | Set module preferences |
| `Get-WingetBatchConfig` | **System** | View module preferences |
| `Start-WingetUpdateCheck` | **Automation** | Manual update check trigger |
| `Update-WingetBatch` | **System** | Self-update the module |

## Usage Examples

### 🧠 AI Recommendations
```powershell
# Persona-based recommendations
Get-WingetRecommend -Persona "data scientist" -Explain

# Clone this machine's personality (what am I missing?)
Get-WingetRecommend -ClonePersonality -MaxResults 10

# Filter by category and install interactively
Get-WingetRecommend -Persona "devops engineer" -Category DevOps -Install
```

### 🌐 REST API Server
```powershell
# Start server (generates API key automatically)
Start-WingetServer -Port 8484

# Then from any HTTP client:
# GET  /api/packages          — list installed
# GET  /api/search?q=python   — search winget
# POST /api/packages/install  — install {"packages": ["Git.Git"]}
# GET  /api/updates           — pending updates
# POST /api/updates/apply     — apply all updates
# GET  /api/state             — machine state
# GET  /api/stats             — package statistics
# GET  /api/health            — server health
```

### 🔧 Scheduled Maintenance
```powershell
# Register weekly Sunday 3AM maintenance
Register-WingetMaintenance -Schedule Weekly -Time 03:00

# Daily updates + drift audit at 2AM
Register-WingetMaintenance -Schedule Daily -Time 02:00 -Action UpdateAll, AuditDrift

# Check status and last run result
Register-WingetMaintenance -Status

# Test run immediately
Register-WingetMaintenance -RunNow

# Remove the task
Register-WingetMaintenance -Unregister
```

### 🕸️ Dependency Graphs
```powershell
# Mermaid diagram for GitHub docs
Get-WingetDependencyGraph -PackageId "Python.Python.3.12" -Format Mermaid

# ASCII tree view
Get-WingetDependencyGraph -PackageId "Microsoft.VisualStudioCode" -Format Tree

# Graphviz DOT for rendering
Get-WingetDependencyGraph -PackageId "Docker.DockerDesktop" -Format DOT -OutputPath ".\deps.dot"

# All installed packages, 2 levels deep
Get-WingetDependencyGraph -AllInstalled -Depth 2 -Format Object
```

### 🖥️ Machine-as-Code
```powershell
# Snapshot golden machine
Get-WingetMachineState -Export -Path ".\golden.json"

# Detect drift on another machine
Get-WingetMachineState -Compare -Path ".\golden.json"

# Reconcile (install missing + update outdated)
Get-WingetMachineState -Reconcile -Path ".\golden.json"
```

### 🚀 Deployment
```powershell
# Batch install with search
Install-WingetAll "nodejs" -Silent

# Idempotent manifest deployment
Invoke-WinGetBatch -Path ".\work-apps.yaml" -ThrottleLimit 6

# Install EVERYTHING from search (dangerous!)
Install-WingetAll "microsoft" -IWantToLiterallyInstallAllFuckingResults
```

### 🔍 Discovery & Monitoring
```powershell
# Live dashboard
Watch-WingetPackages

# New packages from last 7 days
Get-WingetNewPackages -Days 7 -ExportHtml

# Package info
Get-WingetPackageInfo -Id "Git.Git" -ShowVersions

# Find duplicates
Find-WingetDuplicate -IncludeVersions

# Installation history
Get-WingetHistory -Days 30 -Search "python"
```

## Configuration

| File | Purpose |
|:---|:---|
| `~\.wingetbatch\config.json` | Module preferences |
| `~\.wingetbatch\github_token.clixml` | Encrypted GitHub PAT |
| `~\.wingetbatch\update_cache.json` | Update check cache (30m TTL) |
| `~\.wingetbatch\package_cache.json` | Package details cache (30d) |
| `~\.wingetbatch\maintenance\` | Scheduled task reports |
| `~\.wingetbatch\maintenance_task.ps1` | Generated maintenance script |

## Requirements

- **Windows 10/11** with winget (App Installer)
- **PowerShell 5.1+** (7+ recommended)
- **Microsoft.WinGet.Client** (auto-installed)
- **PwshSpectreConsole** (auto-installed)
- **Pode** (auto-installed, only for `Start-WingetServer`)

## Architecture

```
WingetBatch/
├── Public/          # 26 exported commands
├── Private/         # Internal helpers (caching, parsing, jobs, completers)
├── tests/           # Pester test suite (48+ tests)
├── wiki/            # GitHub Wiki documentation
├── docs/            # Architecture design documents
└── .github/         # CI/CD (auto-publish to PSGallery on push)
```

**Key design decisions:**
- COM API (`Microsoft.WinGet.Client`) as primary interface — no CLI text parsing
- Split-phase concurrency: parallel downloads, serialized installs
- Machine-as-Code: declarative state with drift detection and reconciliation
- Local-first AI: heuristic archetype matching, no external services required

## Credits

**WingetBatch** is architected and maintained by **Matthew Bubb**.

## Version History

- **2.8.0** (Current) — AI Recommender, REST API Server, Scheduled Maintenance, Dependency Graphs
- **2.7.0** — Machine-as-Code, Live Dashboard, Package Intelligence, Security Hardening
- **2.5.0** — COM API Migration, Repair-WingetBatchManager
- **2.0.0** — Discovery Engine, Update Notifications, GitHub Auth
- **1.0.0** — Initial batch installation core

## License

MIT — See [LICENSE](LICENSE) for details.
