# WingetBatch Wiki

**WingetBatch** is a PowerShell module that enhances Windows Package Manager (winget) with batch installation, intelligent package discovery, background update notifications, HTML reporting, and secure GitHub authentication.

---

## Overview

WingetBatch transforms winget from a single-package CLI tool into a powerful batch deployment system. Whether you're setting up a new machine, auditing your installed software, or discovering newly published packages, WingetBatch provides the tooling to do it efficiently.

### Key Capabilities

| Feature | Description |
|:---|:---|
| **Batch Installation** | Search and install multiple packages in one operation with interactive UI |
| **Package Discovery** | Query the winget-pkgs GitHub repo to find truly new packages |
| **Update Monitoring** | Background update checks with terminal profile integration |
| **HTML Reporting** | Generate professional, standalone HTML audit reports |
| **GitHub Authentication** | Boost API rate limits from 60 to 5,000 requests/hour |
| **Idempotent Deployments** | Manifest-driven deployments via COM API with state verification |

---

## Quick Links

- [[Installation and Setup]] - Get started with WingetBatch
- [[Command Reference]] - Full command documentation with parameters
- [[Configuration]] - Settings, storage locations, and preferences
- [[Architecture]] - Next-generation architecture and design decisions
- [[Troubleshooting]] - Common issues and diagnostic tools

---

## Requirements

- **Windows Package Manager** (winget)
- **PowerShell 5.1** or **PowerShell 7+** (Recommended)
- **Microsoft.WinGet.Client** module (auto-installed as dependency)
- **PwshSpectreConsole** module (auto-installed if missing)

---

## Current Version

**v2.7.0** - Machine-as-Code & Developer Experience.

### What's New in v2.7.0
- **Machine-as-Code**: Snapshot, compare, and reconcile machine package state
- **Live Dashboard**: Real-time terminal monitoring (htop-style)
- **Package Intelligence**: Rich info display, duplicate detection, history timeline
- **Tab Completion**: Intelligent argument completers for all commands
- **Security Hardening**: Eliminated Invoke-Expression, fixed path injection

See the [[Command Reference]] for full details on all 22 available commands.

---

## License

MIT License - Copyright (c) 2025 Matthew Bubb
