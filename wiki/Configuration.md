# Configuration

WingetBatch stores all configuration, credentials, and cache data in a dedicated directory on your system.

---

## Storage Location

All WingetBatch data is stored in:

```
~\.wingetbatch\
```

This expands to `C:\Users\<YourUsername>\.wingetbatch\` on most systems.

---

## File Structure

| File | Purpose | Format |
|:---|:---|:---|
| `config.json` | Module settings and notification preferences | JSON |
| `github_token.clixml` | AES-encrypted GitHub Personal Access Token | CliXml (SecureString) |
| `github_ratelimit.json` | API rate limit tracking with hourly rollover | JSON |
| `package_cache.json` | 30-day package details cache | JSON |
| `update_cache.json` | Cached update check results (30-min TTL) | JSON |

---

## Configuration Settings

### Viewing Configuration

```powershell
# Display current configuration
Get-WingetBatchConfig
```

### Modifying Configuration

```powershell
# Set a configuration value
Set-WingetBatchConfig -Key "SettingName" -Value "NewValue"
```

### Backup and Restore

```powershell
# Export configuration to a backup file
Export-WingetBatchConfig -Path ".\wingetbatch-backup.json"

# Restore from a backup
Import-WingetBatchConfig -Path ".\wingetbatch-backup.json"
```

---

## Update Notification Settings

When you run `Enable-WingetUpdateNotifications`, the following is configured:

- **Interval**: How often to check for updates (in hours)
- **Profile Integration**: A script block is added to your PowerShell profile to display cached notifications on terminal startup

### Cache Behavior

- Update check results are cached for **30 minutes** (TTL)
- Use `Get-WingetUpdates -Force` to bypass the cache
- The background check respects the configured interval to avoid excessive API calls

---

## GitHub Authentication

### Token Storage

Tokens are stored using PowerShell's `Export-Clixml` with SecureString serialization:

- **Encryption**: AES-256 via Windows DPAPI
- **Binding**: Locked to your Windows user account (not portable across machines)
- **Location**: `~\.wingetbatch\github_token.clixml`

### Rate Limits

| Authentication | Requests/Hour |
|:---|:---|
| Unauthenticated | 60 |
| Authenticated (PAT) | 5,000 |

Rate limit state is tracked in `github_ratelimit.json` with automatic hourly rollover.

### Managing Tokens

```powershell
# Create token via interactive OAuth
New-WingetBatchGitHubToken

# Set token manually
Set-WingetBatchGitHubToken -Token "ghp_xxxxxxxxxxxxxxxxx"

# Remove stored token
Set-WingetBatchGitHubToken -Remove
```

---

## Package Cache

The package details cache (`package_cache.json`) stores metadata fetched from the winget-pkgs GitHub repository:

- **TTL**: 30 days
- **Contents**: Version, Publisher, License, Pricing, GitHub links, Release Notes, and 20+ fields per package
- **Benefit**: Dramatically faster repeat searches by avoiding redundant API calls

### Clearing the Cache

```powershell
# Full cleanup (cache + temp files)
Invoke-WingetBatchCleanup
```

---

## COM API Search Settings

WingetBatch uses the `Microsoft.WinGet.Client` COM API for package searches. The default search behavior can be configured:

| Setting | Default | Description |
|:---|:---|:---|
| `SearchMatchOption` | `ContainsCaseInsensitive` | How search terms match against package fields |
| `LimitResult` | `100` | Maximum results returned per search |

### Smart Scope Routing

For purely numeric queries, WingetBatch automatically bypasses "Id" and "Moniker" fields while retaining Tag matching to avoid false positives.
