# WingetBatch

**The ultimate Windows Package Manager power tool.** 34 commands for AI-powered recommendations, fleet management, machine-as-code, REST API server, rollback engine, compliance policies, health scoring, offline deployment, community profiles, and more.

```powershell
Install-Module WingetBatch
```

## Why WingetBatch?

| You want to... | Command |
|:---|:---|
| "Set up this PC like a backend dev" | `Get-WingetRecommend -Persona "backend dev" -Install` |
| "Update all 12 lab machines" | `Invoke-WingetFleet -ComputerFile .\lab.txt -Action UpdateAll` |
| "Undo the last 3 installs" | `Restore-WingetSnapshot -UndoLast 3` |
| "Is this machine compliant?" | `Test-WingetCompliance -PolicyPath .\policy.json` |
| "Should I trust this package?" | `Get-WingetHealthScore -PackageId "Some.Tool" -Detailed` |
| "Notify Discord when updates land" | `Send-WingetWebhook -Platform Discord -Event UpdatesAvailable` |
| "Deploy to air-gapped machines" | `Export-WingetOffline -FromInstalled -Deploy` |
| "Install a community setup profile" | `Install-WingetProfile -Url "https://..."` |
| "What changed in VS Code 1.94→1.95?" | `Get-WingetChangelog -PackageId "Microsoft.VisualStudioCode"` |
| "Manage packages over HTTP" | `Start-WingetServer -Port 8484` |
| "Auto-update every Sunday at 3AM" | `Register-WingetMaintenance` |
| "Snapshot & replicate this machine" | `Get-WingetMachineState -Export -Path .\golden.json` |

## All 34 Commands

### AI & Intelligence
| Command | Description |
|:---|:---|
| `Get-WingetRecommend` | Persona-based + personality-clone package recommendations |
| `Get-WingetHealthScore` | Package trustworthiness rating (0-100, A+ to F) |
| `Get-WingetChangelog` | Version history and release notes diff |
| `Get-WingetDependencyGraph` | Dependency visualization (Mermaid/DOT/Tree) |

### Fleet & Automation
| Command | Description |
|:---|:---|
| `Invoke-WingetFleet` | Push operations to N machines over WinRM/SSH |
| `Register-WingetMaintenance` | Scheduled auto-update maintenance tasks |
| `Start-WingetServer` | REST API server for remote management (Pode) |
| `Send-WingetWebhook` | Discord/Slack/Teams event notifications |

### State & Compliance
| Command | Description |
|:---|:---|
| `Get-WingetMachineState` | Snapshot, compare, reconcile machine state |
| `Restore-WingetSnapshot` | Package-level rollback (undo/restore/diff) |
| `Test-WingetCompliance` | Policy engine (required/banned/version floors) |
| `Install-WingetProfile` | Shareable community setup profiles |

### Deployment
| Command | Description |
|:---|:---|
| `Install-WingetAll` | Batch install from search results |
| `Invoke-WinGetBatch` | Idempotent manifest-driven deployments |
| `Export-WingetOffline` | Air-gapped offline package repository |
| `Get-WingetUpdates` | Check and install available updates |

### Discovery & Monitoring
| Command | Description |
|:---|:---|
| `Get-WingetNewPackages` | Find truly new packages on winget |
| `Get-WingetPackageInfo` | Rich brew-info-style package explorer |
| `Watch-WingetPackages` | Live terminal dashboard (htop-style) |
| `Find-WingetDuplicate` | Detect duplicates and version clusters |
| `Get-WingetHistory` | Installation history timeline |

### System & Config
| Command | Description |
|:---|:---|
| `Enable-WingetUpdateNotifications` | Background update monitoring |
| `Disable-WingetUpdateNotifications` | Disable monitoring |
| `Set-WingetBatchGitHubToken` | Set/remove GitHub API token |
| `New-WingetBatchGitHubToken` | Interactive GitHub OAuth |
| `Remove-WingetRecent` | Uninstall recently added packages |
| `Invoke-WingetBatchCleanup` | Clean cache and temp files |
| `Repair-WingetBatchManager` | Diagnose and repair winget |
| `Export-WingetBatchConfig` | Backup configuration |
| `Import-WingetBatchConfig` | Restore configuration |
| `Set-WingetBatchConfig` | Set preferences |
| `Get-WingetBatchConfig` | View preferences |
| `Start-WingetUpdateCheck` | Manual update check |
| `Update-WingetBatch` | Self-update module |

## Quick Examples

```powershell
# AI: "I'm a data scientist" — get scored recommendations
Get-WingetRecommend -Persona "data scientist" -Explain -Install

# Fleet: Update all machines in the lab
Invoke-WingetFleet -ComputerFile ".\lab.txt" -Action UpdateAll -ExportReport ".\report.json"

# Rollback: Undo last 3 changes
Restore-WingetSnapshot -UndoLast 3

# Compliance: Test against company policy
Test-WingetCompliance -PolicyPath ".\policy.json" -Remediate

# Health: Audit all installed packages
Get-WingetHealthScore -AllInstalled -MinScore 50

# Offline: Create USB deployment stick
Export-WingetOffline -FromInstalled -OutputPath "E:\AirGap" -Deploy

# Profile: Install the DevOps toolkit
Install-WingetProfile -Name DevOps

# API: Start remote management server
Start-WingetServer -Port 8484

# Changelog: What's new in Git?
Get-WingetChangelog -PackageId "Git.Git" -Limit 5

# Machine-as-Code: Golden image
Get-WingetMachineState -Export -Path ".\golden.json"
Get-WingetMachineState -Reconcile -Path ".\golden.json"  # On new PC
```

## Requirements

- Windows 10/11 with winget
- PowerShell 5.1+ (7+ recommended)
- Auto-installed: Microsoft.WinGet.Client, PwshSpectreConsole, Pode (for API server)

## Architecture

```
WingetBatch/
├── Public/          # 34 exported commands
├── Private/         # Internal helpers (cache, parsing, jobs, completers)
├── tests/           # Pester test suite
├── wiki/            # GitHub Wiki docs
├── docs/            # Architecture design
└── .github/         # CI/CD → auto-publish to PSGallery
```

## Credits

Architected and maintained by **Matthew Bubb**.

## Version History

- **2.9.0** (Current) — AI Recommender, Fleet Management, Rollback Engine, Compliance, Health Scores, Webhooks, Offline Deploy, Profiles, Changelog
- **2.8.0** — Scheduled Maintenance, Dependency Graphs, REST API Server
- **2.7.0** — Machine-as-Code, Live Dashboard, Package Intelligence, Security Hardening
- **2.5.0** — COM API Migration
- **2.0.0** — Discovery Engine, Update Notifications, GitHub Auth
- **1.0.0** — Initial release

## License

MIT — See [LICENSE](LICENSE).
