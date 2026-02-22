## 2024-11-06 - [CLI Output UX]
**Learning:** Users often need the exact command to replicate an action or install a package manually. Hiding it or only showing it conditionally (e.g., Moniker) reduces usability.
**Action:** Always include a "Command" section in detailed package views, providing a copy-pasteable command string (e.g., `winget install --id <ID> -e`).

## 2024-11-06 - [PowerShell Cross-Platform UX]
**Learning:** Using `$env:USERPROFILE` breaks the experience for Linux users (and CI/CD environments).
**Action:** Always use `$HOME` in PowerShell scripts for cross-platform compatibility.
