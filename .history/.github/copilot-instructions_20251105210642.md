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
- **update_cache.json**: Cached update results (30 min TTL)

Cache format example:
```json
{
  "UpdateCount": 5,
  "Updates": [{"Id": "Package.ID", "CurrentVersion": "1.0"}],
  "LastChecked": "2025-11-05T10:30:00Z"
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

## Non-Obvious Behaviors

1. **Multi-word search combines ALL search results** then filters for lines matching ALL words (not a single winget search)
2. **GitHub commit parsing is heuristic** - uses regex patterns that may miss unconventional commit formats
3. **Background update check runs as PowerShell job** - waits max 10 seconds then continues (non-blocking)
4. **Cache TTL is 30 minutes** - updates may show stale data, use `-Force` to bypass
5. **Token validation is optional** - malformed tokens are saved if user confirms
6. **Package ID deduplication** - GitHub commits may reference same package multiple times, tracked with hashtable

## Gotchas When Modifying

- Winget output format varies by locale/version - English assumed
- Regex `^[A-Za-z0-9\.\-_]+$` may reject valid IDs with other characters
- Profile regex pattern `(?s)# WingetBatch.*?Start-WingetUpdateCheck\s*\}` must match injected block exactly
- JSON config files lack error handling - corrupt JSON breaks module
- No transaction safety when writing profile - interruption can corrupt file
- `$LASTEXITCODE` is global - check immediately after winget commands
