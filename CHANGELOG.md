# WingetBatch Changelog

## v2.10.0 - Reliability Release
- REQUIREMENT: PowerShell 7.4+ is now declared (PwshSpectreConsole already required it; 11 commands never parsed on 5.1).
- FIXED: Installs/updates/uninstalls reported success when the installer failed. WinGet returns a Status instead of throwing; every command now checks it and shows the real error and reboot requirement.
- FIXED: Modules that export the same command names (e.g. Cobalt) hijacked Get-WinGetPackage, so Get-WingetUpdates always said "up to date". All WinGet calls are now module-qualified.
- FIXED: Get-WingetMachineState failed on every call (helpers defined after use). -RemoveExtraneous now only touches WinGet-sourced packages and lists them first; pinned versions are honored; new -Force and -IncludeUnmanaged.
- FIXED: Get-WingetDependencyGraph failed on every call (wrong parameter name); tree output and Mermaid labels fixed.
- FIXED: Get-Date -ToString (invalid) broke Restore-WingetSnapshot -Take, Invoke-WingetFleet, Send-WingetWebhook (Discord), Test-WingetCompliance reports, Export-WingetOffline and the maintenance task.
- FIXED: Register-WingetMaintenance tasks never updated anything (called the interactive Get-WingetUpdates). -IncludeStore, NotifyOnly (webhooks) and Monthly schedules now work.
- FIXED: Start-WingetServer used a non-existent Pode cmdlet (Add-PodeRouteMiddleware); routes no longer call interactive commands; crypto-random API key; -Https uses a self-signed certificate.
- FIXED: Get-WingetNewPackages used local time as UTC, shifting the search window by the UTC offset; background detail jobs never received the parser, losing descriptions and licenses.
- FIXED: Get-WingetPackageInfo -ShowManifest/-ShowVersions, Get-WingetChangelog release notes and Get-WingetHealthScore manifest checks read the wrong files; version lists sorted as text (9.x above 10.x).
- FIXED: Get-WingetHealthScore flagged almost every package as pre-release ("Source" contains "rc") and scored freshness by version count; it now uses the real last-commit date.
- FIXED: Install-WingetProfile -Path could not load its own -Export output; 20 built-in profile/recommendation IDs did not exist in winget.
- FIXED: Enable-WingetUpdateNotifications overwrote config.json (losing webhooks and search settings). Config writes now merge.
- FIXED: Invoke-WinGetBatch ignored version pins and ran a download phase whose files were never used (and which always failed). -ThrottleLimit is now ignored.
- FIXED: Remove-WingetRecent could attach the wrong install date via loose name matching; now uses the COM API and exact/registry-key matching.
- FIXED: Export-WingetOffline ignored -Architecture and ran MSIs without msiexec; now built on Export-WinGetPackage with hash verification and per-installer silent switches.
- FIXED: Invoke-WingetFleet lost machine names on failure and -RetryFailed ignored -UseSSH; timeouts reported.
- FIXED: Test-WingetCompliance -NewPolicy -PolicyPath could not bind; Send-WingetWebhook -SaveConfig prompted for -Event; Teams now uses Adaptive Cards.
- FIXED: Watch-WingetPackages -Once crashed when output was redirected; showed 0 updates and misaligned borders.
- NEW: Get-WingetUpdates -ListOnly, Get-WingetHistory -PassThru, Restore-WingetSnapshot -RestoreVersions/-Force, Install-WingetProfile -Force.
- NEW: -AutoSnapshot now actually snapshots before every WingetBatch install/update/uninstall; -UndoLast 1 undoes the latest one.
- NEW: Update notifications share the update cache with Get-WingetUpdates, so it opens instantly after a background check.
- LIVE-TESTED against real installs, updates, uninstalls, downloads and a running API server. Fixes from that pass:
  * Results are verified, not trusted: an update that leaves the old version reports NotUpdated, an uninstall that leaves the program reports StillInstalled (both happen in practice with WinGet 1.30).
  * Pinning/rollback to an older version uninstalls first, then installs and verifies (installing over the top left two registered copies of VLC).
  * ARP\ and MSIX\ packages (Add/Remove Programs entries) can be updated/uninstalled; WinGet's ID search rejects those IDs.
  * Install-WingetAll -Id is an exact match (VideoLAN.VLC also installed VideoLAN.VLC.Nightly); summary table renders colors.
  * Start-WingetServer: never started ($using in the main Pode block), API-key check read a non-existent property, /api/health crashed, rate limit was per-thread, result counts were wrong. Errors now log to ~/.wingetbatch/server_errors_*.log; responses carry X-RateLimit-Remaining.
  * Invoke-WingetFleet: an edit had left the old implementation in place; machine names and per-package errors now reported.
  * Install-Offline.ps1 accepts "-PackageId a,b" from powershell.exe -File / cmd.
  * winget show parsing handles multi-line Description, Tags and Release Notes.
  * Pode/WinGet.Client/WingetBatch installs and Update-WingetBatch work with PSResourceGet without prompting.
  * Get-WingetChangelog processes every piped package ID.
- TESTS: 30 new regression tests (78 total).

## v2.9.0 - The Full Arsenal
- NEW: Get-WingetRecommend - AI-powered package recommendations (persona matching + personality clone).
- NEW: Invoke-WingetFleet - SCCM-lite fleet management over WinRM/SSH.
- NEW: Restore-WingetSnapshot - Package-level rollback engine (undo, restore, diff).
- NEW: Test-WingetCompliance - Policy/compliance engine (required, banned, version floors).
- NEW: Get-WingetHealthScore - Package trustworthiness rating (0-100, A+ through F).
- NEW: Send-WingetWebhook - Discord/Slack/Teams notifications for package events.
- NEW: Export-WingetOffline - Air-gapped offline package deployment with hash verification.
- NEW: Install-WingetProfile - Shareable community setup profiles (8 built-in).
- NEW: Get-WingetChangelog - Version history and release notes diff between versions.
- 34 total commands. Author/Architect: Matthew Bubb.

## v2.8.0 - Automation, Visualization & Remote Management
- NEW: Register-WingetMaintenance - Scheduled maintenance tasks for automatic package updates.
  * Daily/Weekly/Monthly recurrence with configurable time and actions.
  * Actions: UpdateAll, UpdateOutdated, CleanupTemp, AuditDrift, NotifyOnly.
  * JSON reports with 30-report retention. Runs as SYSTEM or current user.
  * -Status, -Unregister, -RunNow for full lifecycle management.
- NEW: Get-WingetDependencyGraph - Package dependency graph visualization.
  * Output formats: Mermaid (GitHub/docs), DOT (Graphviz), ASCII Tree, Object.
  * Circular dependency detection and highlighting.
  * Fetches dependency data from winget-pkgs GitHub manifests.
  * Configurable depth, external dependency inclusion, and file output.
- NEW: Start-WingetServer - REST API server for remote package management (Pode).
  * Full CRUD: install, uninstall, update, search packages over HTTP.
  * Endpoints: /api/packages, /api/updates, /api/state, /api/history, /api/stats.
  * API key authentication, rate limiting, request logging.
  * Self-documenting: GET / returns full endpoint catalog.
- Author/Architect: Matthew Bubb.

## v2.7.0 - Machine-as-Code & Developer Experience
- NEW: Get-WingetMachineState - Full machine state snapshot, drift comparison, and reconciliation (Machine-as-Code).
  * Export installed packages to portable JSON/YAML manifests.
  * Compare current state against a golden baseline for drift detection.
  * Reconcile: auto-install missing, update outdated, optionally remove extraneous packages.
- NEW: Get-WingetPackageInfo - Rich brew-info-style package explorer with GitHub manifest fetching.
- NEW: Get-WingetHistory - Installation history timeline from registry and winget logs.
- NEW: Watch-WingetPackages - Live terminal dashboard (htop-style) for package monitoring.
- NEW: Find-WingetDuplicate - Detect duplicate packages, multi-source installs, and version clusters.
- NEW: Tab-completion argument completers for package IDs across all commands.
- SECURITY: Eliminated all Invoke-Expression usage in Invoke-WinGetBatch (command injection fix).
- SECURITY: Replaced hardcoded paths with dynamic environment resolution.
- FIXED: Package deduplication bug in Install-WingetAll (duplicates were shown and installed).
- ENHANCED: Installation progress counter [N/M] for all batch operations.
- ENHANCED: Invoke-WinGetBatch now uses COM API as primary install path with CLI fallback.
- Author/Architect: Matthew Bubb.

## v2.6.0 - Smart Search Architecture
- ENHANCED: Smart Scope Routing implemented in Install-WingetAll. Purely numeric queries automatically bypass "Id" and "Moniker" fields while retaining Tag matching.
- NEW: Added -LimitResult (default 100) mapped natively to COM API Count parameter, ending searches early to massively boost performance.
- NEW: Added -Id parameter to easily specify specific exact IDs instead of wildcard queries.
- NEW: Added SQLite cache fragmentation check directly in Install-WingetAll logic with automated rebuild recommendations.
- NEW: Implemented Set-WingetBatchConfig and Get-WingetBatchConfig module preferences.
- ENHANCED: Dynamic config-driven COM SearchMatchOption override. ContainsCaseInsensitive remains default.
- FIXED: Microsoft.WinGet.Client\Find-WinGetPackage forced namespace avoids naming collisions with shadowing modules (like Cobalt).

## v2.5.0 - COM API Migration (Breaking Fix)
- CRITICAL FIX: Migrated all core functions from winget.exe CLI text-parsing to Microsoft.WinGet.Client COM API.
  * Install-WingetAll now uses Find-WinGetPackage (COM) instead of parsing 'winget search' text output.
  * Get-WingetUpdates now uses Get-WinGetPackage (COM) instead of parsing 'winget upgrade' text output.
  * Installation now uses Install-WinGetPackage (COM) instead of shelling out to winget.exe.
  * Updates now use Update-WinGetPackage (COM) instead of shelling out to winget.exe.
  * This eliminates all dependency on winget.exe being in PATH (a known Windows update regression).
- NEW: Repair-WingetBatchManager - Diagnostic and self-repair tool for common winget issues.
  * Checks winget.exe PATH, Microsoft.WinGet.Client module, COM API health.
  * Auto-repairs by re-registering App Installer and fixing PATH.
- ENHANCED: Background detail jobs now resolve winget.exe by known filesystem paths with COM API fallback.
- ENHANCED: Added --no-progress and --disable-interactivity flags to all remaining CLI calls for cleaner output.
- DEPENDENCY: Microsoft.WinGet.Client is now a required module (auto-installed with WingetBatch).
- Author/Architect: Matthew Bubb. All credit for this architectural migration is attributed solely to him.

## v2.4.0 - Security Update & Massive Feature Bloat
- FIXED: Replaced unsafe Invoke-Expression with argument array execution in Invoke-WinGetBatch.
- FIXED: Fallback PS5.1 execution for ForEach-Object -Parallel downloads.
- FIXED: Array casting fixes and character encoding parsing fixes.
- NEW: Get-WingetHoroscope - Predict the celestial fate of your package updates.
- NEW: Invoke-WingetRussianRoulette - Installs a completely random package from the Winget repository.
- NEW: Convert-WingetPackageToHaiku - Generates a 5-7-5 syllable poem for any package.
- NEW: Show-WingetMatrix - Displays your installed packages cascading down the screen like The Matrix.
- NEW: Test-WingetPackageVibes - Arbitrary algorithmic vibe check for Winget packages (Corporate = Cringe).

## v2.3.0 - Next-Generation Idempotent Deployment Engine
- NEW: Invoke-WinGetBatch - Idempotent, manifest-driven package deployments using native COM APIs.
  * Decoupled from fragile CLI regex parsing; uses Microsoft.WinGet.Client COM interfaces.
  * Split-Phase Concurrency: Parallel downloads via native PowerShell 7 ForEach-Object -Parallel with serial, collision-free background installations.
  * High-fidelity target state configuration parsing from standard JSON and YAML manifests.
  * Diagnostic exit code mapping (standardizing successful exits 0, pending reboots 3010/1641, and failures).
  * Forensic and auditing: compilation of structured JSON deployment reports containing detailed per-package status telemetry.
  * Full integration with the winget batch environment and standalone distribution channels.
  * Author/Architect: Matthew Bubb. All credit for this next-generation design is attributed solely to him.

## v2.0.0 - Major Feature Release
- NEW: Get-WingetNewPackages - Discover recently added packages from winget-pkgs GitHub repository
  * GitHub API integration with pagination support
  * Parallel background job system (max 10 concurrent) for fetching package details
  * Smart job waiting - only waits for jobs with selected packages
  * 30-day package details caching system for faster repeat searches
  * Comprehensive package info: Version, Publisher, GitHub links, License, Pricing, Release Notes, and 20+ fields
  * Interactive re-selection with preserved package information
  * Exclusion filter support to hide specific packages/publishers
  * API rate limit tracking with hourly rollover
  * GitHub token support for 5,000 req/hour (vs 60 unauthenticated)

- NEW: Remove-WingetRecent - Uninstall recently installed packages by date
  * Reads from Windows Registry (HKLM/HKCU Uninstall keys)
  * Filter by installation date (e.g., -Days 7 for last week)
  * Interactive selection of packages to remove

- ENHANCED: Install-WingetAll
  * Now uses --silent flag for cleaner output
  * Improved error handling and reporting

- ENHANCED: Profile Integration
  * Background update checks with cached results
  * 30-minute cache TTL for update notifications

- NEW: Token Management
  * Set-WingetBatchGitHubToken - Store GitHub PAT securely (AES encrypted CliXml)
  * New-WingetBatchGitHubToken - Interactive token creation wizard with masked input

- FIXED: Date parsing bug in API rate limit tracking (timezone handling)
- FIXED: Package selection workflow when going back to change selections

Configuration stored in: ~/.wingetbatch/
  - config.json - Update notification settings
  - github_token.clixml - Secure GitHub Personal Access Token
  - github_ratelimit.json - API usage tracking
  - package_cache.json - 30-day package details cache
  - update_cache.json - Cached update results

Requires: PowerShell 7.4+, Microsoft.WinGet.Client, PwshSpectreConsole
