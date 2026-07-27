# Troubleshooting

Common issues and their solutions when using WingetBatch.

---

## Diagnostic Tool

WingetBatch includes a built-in diagnostic and repair tool:

```powershell
Repair-WingetBatchManager
```

This tool automatically checks:
- `winget.exe` PATH availability
- `Microsoft.WinGet.Client` module installation status
- COM API health and responsiveness
- App Installer registration

If issues are found, it attempts auto-repair by re-registering App Installer and fixing PATH.

---

## Common Issues

### "winget is not recognized as a command"

**Cause:** After a Windows Update, `winget.exe` may be removed from PATH.

**Solution:**
```powershell
# Run the built-in repair tool
Repair-WingetBatchManager
```

**Manual fix:**
1. Open Settings > Apps > Advanced app settings
2. Find "App Installer" and click Modify/Repair
3. Restart your terminal

> **Note:** Since v2.5.0, WingetBatch uses the COM API and no longer depends on `winget.exe` being in PATH for core operations.

---

### "Microsoft.WinGet.Client module not found"

**Cause:** The required COM API module isn't installed.

**Solution:**
```powershell
# Install manually
Install-Module -Name Microsoft.WinGet.Client -Scope CurrentUser

# Or let WingetBatch handle it
Repair-WingetBatchManager
```

---

### GitHub API Rate Limit Exceeded

**Symptoms:** `Get-WingetNewPackages` returns errors about rate limiting or returns incomplete results.

**Solution:**
```powershell
# Authenticate to boost limits from 60 to 5,000 req/hour
New-WingetBatchGitHubToken

# Verify your token is stored
Get-WingetBatchConfig
```

**Check current rate limit status:**
- Rate limit data is tracked in `~\.wingetbatch\github_ratelimit.json`
- Limits reset automatically every hour

---

### PwshSpectreConsole Not Found

**Symptoms:** Interactive UI elements fail to render or throw module-not-found errors.

**Solution:**
```powershell
# Install manually
Install-Module -Name PwshSpectreConsole -Scope CurrentUser

# Re-import WingetBatch
Import-Module WingetBatch -Force
```

---

### Update Notifications Not Appearing

**Symptoms:** After enabling notifications, nothing shows when opening a new terminal.

**Troubleshooting steps:**

1. **Verify notifications are enabled:**
   ```powershell
   Get-WingetBatchConfig
   ```

2. **Check your PowerShell profile contains the integration:**
   ```powershell
   Get-Content $PROFILE | Select-String "WingetBatch"
   ```

3. **Force a manual update check:**
   ```powershell
   Start-WingetUpdateCheck
   ```

4. **Clear the update cache:**
   ```powershell
   Invoke-WingetBatchCleanup
   ```

5. **Re-enable notifications:**
   ```powershell
   Disable-WingetUpdateNotifications
   Enable-WingetUpdateNotifications
   ```

---

### Module Import Failures

**Symptoms:** `Import-Module WingetBatch` throws errors.

**Solution:**
```powershell
# Force reimport with verbose output
Import-Module WingetBatch -Force -Verbose

# Check for dependency issues
Get-Module -ListAvailable WingetBatch | Select-Object -ExpandProperty RequiredModules

# Nuclear option: reinstall
Uninstall-Module WingetBatch -AllVersions
Install-Module WingetBatch -Scope CurrentUser
```

---

### SQLite Cache Fragmentation

**Symptoms:** Slow search performance over time.

**Solution:**
WingetBatch v2.6.0+ includes automatic SQLite cache fragmentation detection. If fragmentation is detected during `Install-WingetAll`, a rebuild recommendation is displayed.

**Manual cache reset:**
```powershell
# Clear all caches
Invoke-WingetBatchCleanup

# Reset winget source cache
winget source reset --force
```

---

### COM API Errors

**Symptoms:** Operations fail with COM-related exceptions.

**Solution:**
```powershell
# Run diagnostics
Repair-WingetBatchManager

# Re-register App Installer (admin required)
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
```

---

## Getting Help

1. Run `Repair-WingetBatchManager` first - it resolves most common issues
2. Check the [GitHub Issues](https://github.com/thebubbsy/WingetBatch/issues) for known problems
3. Open a new issue with:
   - PowerShell version (`$PSVersionTable`)
   - Module version (`(Get-Module WingetBatch).Version`)
   - Error output
   - Steps to reproduce
