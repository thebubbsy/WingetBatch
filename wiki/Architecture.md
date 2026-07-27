# Architecture

This page documents the architectural design of WingetBatch, including the next-generation COM API migration and concurrency model.

---

## Current Architecture (v2.5+)

WingetBatch has completed its migration from CLI text-parsing to the native COM API. All core operations now use the `Microsoft.WinGet.Client` module.

### COM API Integration

| Operation | Previous (CLI) | Current (COM) |
|:---|:---|:---|
| Package Search | Parse `winget search` stdout | `Find-WinGetPackage` |
| List Installed | Parse `winget list` stdout | `Get-WinGetPackage` |
| Install | Shell out to `winget.exe install` | `Install-WinGetPackage` |
| Update | Shell out to `winget.exe upgrade` | `Update-WinGetPackage` |

**Benefits:**
- Eliminates dependency on `winget.exe` being in PATH
- Strongly-typed `[PSCustomObject]` outputs
- Native PowerShell pipeline support
- Resilient error handling without regex fragility

---

## Next-Generation Architecture

The next-generation architecture transforms WingetBatch from a CLI wrapper into an enterprise-grade package deployment tool.

### Core Pillars

#### A. COM API (`Microsoft.WinGet.Client`)

Direct binding to native Windows Package Manager COM interfaces:

```powershell
# Native query resolution returning structured objects
$Catalog = New-Object -ComObject "Microsoft.WinGet.Client"
```

This allows direct querying of the local SQLite index and package sources with strongly-typed outputs.

#### B. Split-Phase Concurrency (RunspacePools)

To bypass Windows Installer (MSI/MSIX) execution mutex locks, the execution cycle is split into two asynchronous phases:

1. **Phase 1: Parallel Downloads** - Uses a RunspacePool to parallelize network fetch requests, pre-caching setup packages locally
2. **Phase 2: Serialized Installation Queue** - Dynamically consumes the cache and fires installations sequentially, preventing mutex collision

#### C. Declarative State Management

Manifest-driven deployments via standard JSON or YAML state definitions:

```yaml
# state.yaml
packages:
  - id: Git.Git
    version: latest
  - id: Python.Python.3.11
    version: 3.11.5
```

Prior to execution, the engine verifies local machine state against the target manifest. If the requested package is already present at the correct version, the step is bypassed (idempotency).

#### D. Exit Code Mapping & Telemetry

Standardized handling of third-party installer exit codes:

| Exit Code | Meaning |
|:---|:---|
| `0` | Success |
| `3010` | Success (Reboot Required) |
| `1641` | Success (Reboot Initiated) |
| Other | Captured error with diagnostic telemetry |

---

## System Workflow

```
Invoke-WinGetBatch
    │
    ├── Input: Pipeline (PSCustomObject) or Manifest (YAML/JSON)
    │
    ▼
Resolve Packages via WinGet.Client API
    │
    ▼
Check Local State (Idempotency)
    │
    ├── Already Installed → Skip & Log
    │
    └── Missing/Outdated → Add to Execution Queue
                              │
                              ▼
                    Initialize RunspacePool
                              │
                              ▼
                    Phase 1: Parallel Downloads
                              │
                              ▼
                    Phase 2: Serialized Installation
                              │
                              ▼
                    Capture Exit Codes
                              │
                    ┌─────────┼─────────┐
                    ▼         ▼         ▼
                 Success   Reboot    Error
                  (0)    (3010/1641) (Other)
                    │         │         │
                    └─────────┼─────────┘
                              ▼
                    Compile JSON Report
```

---

## Module Structure

```
WingetBatch/
├── Public/          # Exported functions (user-facing commands)
├── Private/         # Internal helper functions
├── tests/           # Pester test suites
├── docs/            # Architecture documentation
├── WingetBatch.psd1 # Module manifest
└── WingetBatch.psm1 # Module loader (dot-sources Public/ and Private/)
```

### Key Internal Components

| Component | File | Purpose |
|:---|:---|:---|
| Package Details Cache | `Get-PackageDetailsCache.ps1` | 30-day metadata cache |
| GitHub API Rate Tracking | `Get-GitHubApiRequestCount.ps1` | Rate limit monitoring |
| Background Jobs | `Start-PackageDetailJobs.ps1` | Parallel metadata fetching |
| HTML Report Engine | `Export-WingetHtmlReport.ps1` | Standalone report generation |
| Output Parser | `Parse-WingetShowOutput.ps1` | Legacy CLI output parsing |
| Spectre UI Helpers | `ConvertTo-SpectreEscaped.ps1` | Terminal UI formatting |

---

## Design Decisions

1. **COM over CLI**: Eliminates the #1 support issue (winget.exe not in PATH after Windows updates)
2. **Split-phase over full parallel**: MSI/MSIX mutex locks make fully parallel installation unreliable
3. **CliXml over plaintext**: DPAPI-bound encryption provides hardware-level security without external dependencies
4. **GitHub API over winget source**: The winget-pkgs repository is the canonical source of truth for new package additions
5. **30-day cache TTL**: Balances freshness with API rate limit conservation
