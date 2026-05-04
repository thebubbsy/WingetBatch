# WingetBatch PowerShell Module - AI Agent Instructions

## Architecture Overview

**WingetBatch** is a single-file PowerShell module (`WingetBatch.psm1`) that wraps Windows Package Manager (winget) with batch operations, update monitoring, and GitHub integration. The module has no dependencies except `PwshSpectreConsole` (auto-installed for UI).

### Core Components
- **Batch Installer**: `Install-WingetAll` - Searches winget, parses table output, presents interactive selection with silenced output (--silent)
- **Update Monitor**: `Get-WingetUpdates` + profile integration - Background checks with cached results
- **New Package Discovery**: `Get-WingetNewPackages` - GitHub API integration with parallel background job system, comprehensive package details (20+ fields), and clickable URLs
- **Recent Package Removal**: `Remove-WingetRecent` - Windows Registry-based uninstall by installation date
- **Configuration System**: JSON files in `~\.wingetbatch\` for persistence and API rate limit tracking

### Data Flow Pattern
1. Execute winget CLI → capture stdout/stderr
2. Parse fixed-width table output using column positions from header
3. Extract package IDs with regex validation
4. Present to user via PwshSpectreConsole multi-selection
5. Install selected packages one-by-one with error tracking

## Critical Conventions

### Winget Table Parsing (FRAGILE)
All functions depend on parsing winget's fixed-width table format:
```
Name               Id                  Version
------------------------------------------------
Python 3.12        Python.Python.3.12  3.12.0
```

**Pattern used throughout**:
1. Find header line matching `^Name\s+Id\s+`
2. Record column positions: `IdColStart`, `IdColEnd`
3. Find separator line (`^-+`) to mark data start
4. Extract substring from each line at recorded positions
5. Validate with `^[A-Za-z0-9\.\-_]+$` regex

**If winget CLI output changes, all parsing breaks**. Search for `$line.IndexOf('Id')` to find affected code.

### Package ID Filtering
Multi-word searches use AND logic:
```powershell
# "python dev" requires both words present
$matchesAll = $true
foreach ($word in $searchWords) {
    if ($line -notmatch "(?i)$([regex]::Escape($word))") {
        $matchesAll = $false
    }
}
```

### GitHub API Integration
- **Rate Limits**: 60 req/hr unauthenticated, 5,000 with token
- **Token Storage**: Plain text in `~\.wingetbatch\github_token.txt`
- **Commit Parsing**: Looks for patterns like `New package: Name version X.X.X` in commit messages
- **Pagination**: Fetches ALL pages with `per_page=100` until empty response

### PowerShell Profile Integration
`Enable-WingetUpdateNotifications` injects this code block into `$PROFILE.CurrentUserAllHosts`:
```powershell
# WingetBatch - Update Notifications
if (Get-Module -ListAvailable -Name WingetBatch) {
    Import-Module WingetBatch -ErrorAction SilentlyContinue
    Start-WingetUpdateCheck
}
```
Profile modification uses regex pattern matching to detect/remove existing blocks.

## Configuration & Cache Files

All stored in `$env:USERPROFILE\.wingetbatch\`:
- **config.json**: Notification settings (interval, last check time)
- **github_token.txt**: GitHub PAT (plain text)
- **github_ratelimit.json**: API request tracking with hourly rollover (RequestCount, CurrentHour)
- **update_cache.json**: Cached update results (30 min TTL)

Cache format example:
```json
{
  "UpdateCount": 5,
  "Updates": [{"Id": "Package.ID", "CurrentVersion": "1.0"}],
  "LastChecked": "2025-11-05T10:30:00Z"
}
```

Rate limit tracking format:
```json
{
  "RequestCount": 42,
  "CurrentHour": "2025-01-05T14:00:00Z"
}
```

## Development Workflows

### Testing Module Changes
```powershell
# Reload module after edits
Import-Module .\WingetBatch.psm1 -Force

# Test with WhatIf
Install-WingetAll "python" -WhatIf

# Test error handling (invalid search)
Install-WingetAll "xyzinvalidpackage123"
```

### Debugging Winget Parsing
Add debug output to see parsed columns:
```powershell
Write-Host "IdColStart: $idColStart, IdColEnd: $idColEnd" -ForegroundColor Yellow
Write-Host "Extracted ID: [$packageId]" -ForegroundColor Yellow
```

### Testing GitHub API Features
```powershell
# Test without token (rate limit)
Get-WingetNewPackages -Days 1

# Test with token
Set-WingetBatchGitHubToken -Token "ghp_test"
Get-WingetNewPackages -Days 30
```

### Profile Integration Testing
```powershell
# Enable notifications
Enable-WingetUpdateNotifications

# Check profile was modified
Get-Content $PROFILE.CurrentUserAllHosts | Select-String "WingetBatch"

# Test background check manually
Start-WingetUpdateCheck
```

## Common Patterns & Idioms

### UI Pattern with PwshSpectreConsole
```powershell
# Always check if module is available
if (Get-Module -Name PwshSpectreConsole) {
    $selected = Read-SpectreMultiSelection `
        -Title "[cyan]Title[/]" `
        -Choices $items `
        -PageSize 20 `
        -Color "Green"
}
else {
    # Fallback: plain text display
    Write-Host "Install PwshSpectreConsole for interactive selection"
}
```

### Error Tracking Pattern
Used in all install loops:
```powershell
$successCount = 0
$failCount = 0

foreach ($package in $packages) {
    winget install --id $package
    if ($LASTEXITCODE -eq 0) {
        $successCount++
    } else {
        $failCount++
    }
}

# Always show summary
Write-Host "Success: $successCount | Failed: $failCount"
```

### GitHub Rate Limit Detection
```powershell
catch {
    if ($_.Exception.Response.StatusCode -eq 403 -or $_ -match 'rate limit') {
        Write-Host "⚠ GitHub API Rate Limit Exceeded"
        Write-Host "Run New-WingetBatchGitHubToken to increase limits"
    }
}
```

## Key Files & Their Roles

- **WingetBatch.psm1**: All function implementations (monolithic design)
- **WingetBatch.psd1**: Module manifest with exported functions and metadata
- **README.md**: User documentation with examples
- No separate test files - testing done manually with WhatIf/validation

## Integration Points

### External Dependencies
- **winget CLI**: Must be in PATH, commands must exit with code 0 for success
- **PwshSpectreConsole**: Optional UI enhancement, auto-installed if missing
- **GitHub API**: `https://api.github.com/repos/microsoft/winget-pkgs/commits`

### PowerShell Profile
Module modifies `$PROFILE.CurrentUserAllHosts` for background checks. Always test profile changes don't break shell startup.

### Windows Integration
- Module installed to standard PowerShell module path
- Configuration directory follows Windows conventions (`%USERPROFILE%\.wingetbatch`)

## Parallel Processing Architecture (Get-WingetNewPackages)

### Background Job System
When `Get-WingetNewPackages` discovers packages from GitHub commits, it immediately starts background jobs to fetch detailed information using `winget show --id <PackageId>` BEFORE showing the selection UI. This ensures jobs are processing while the user makes selections.

### Job Pooling Strategy
- **Max 10 concurrent jobs** to prevent system overload
- Packages evenly distributed across jobs (batches of N/10)
- Job package mapping stored: `$jobPackageMap[$job.Id] = $packageBatch`
- Sequential distribution maintains display order (top to bottom)

### Smart Job Waiting
After user selects packages:
1. Categorize jobs as "relevant" (contains selected package) or "irrelevant" (none selected)
2. Only wait for relevant jobs (with 30-second timeout)
3. Stop irrelevant jobs immediately to free resources
4. Check job state first - if already completed, retrieve immediately without waiting

### Comprehensive Package Information
Parses 20+ fields from `winget show` output:
- **Core**: Version, Publisher, PublisherUrl, PublisherGitHub (auto-detected)
- **Metadata**: Author, Moniker, Tags, ShortDescription, License, LicenseUrl
- **Categorization**: Category, Pricing, FreeTrial, StoreLicense, Agreements
- **Content**: Description (full text), ReleaseNotes (full text), ReleaseNotesUrl
- **URLs**: Homepage, PackageUrl, PrivacyUrl, Copyright

Publisher GitHub URL automatically extracted when PublisherUrl matches `github.com/*` pattern.

### Field Parsing Pattern
```powershell
# Extract field with label matching
$line = $output | Where-Object { $_ -match '^Field Name:\s*(.+)$' }
if ($line) { $value = $matches[1].Trim() }
```

### Package Link Display
After selection, shows clickable URLs for each package:
- Primary: Publisher homepage (if available)
- Fallback: winget.run community page
- GitHub manifest URL for advanced users

## Non-Obvious Behaviors

1. **Multi-word search combines ALL search results** then filters for lines matching ALL words (not a single winget search)
2. **GitHub commit parsing is heuristic** - uses regex patterns that may miss unconventional commit formats
3. **Background update check runs as PowerShell job** - waits max 10 seconds then continues (non-blocking)
4. **Cache TTL is 30 minutes** - updates may show stale data, use `-Force` to bypass
5. **Token validation is optional** - malformed tokens are saved if user confirms
6. **Package ID deduplication** - GitHub commits may reference same package multiple times, tracked with hashtable
7. **Background jobs start BEFORE selection UI** - optimizes waiting time by processing during user interaction
8. **Job pooling limits to 10 concurrent jobs** - prevents overwhelming the system with 30+ parallel winget processes
9. **Smart waiting only blocks for relevant jobs** - irrelevant jobs (not selected) are stopped immediately
10. **Sequential package processing** - packages processed in display order (top to bottom) for consistent UX
11. **Full text descriptions** - no truncation on Description or ReleaseNotes fields for complete information
12. **API request tracking** - GitHub API usage counted with hourly rollover stored in github_ratelimit.json

## Gotchas When Modifying

- Winget output format varies by locale/version - English assumed
- Regex `^[A-Za-z0-9\.\-_]+$` may reject valid IDs with other characters
- Profile regex pattern `(?s)# WingetBatch.*?Start-WingetUpdateCheck\s*\}` must match injected block exactly
- JSON config files lack error handling - corrupt JSON breaks module
- No transaction safety when writing profile - interruption can corrupt file
- `$LASTEXITCODE` is global - check immediately after winget commands
