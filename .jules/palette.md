## 2024-05-18 - [CLI Package Detail UX] Duplicate Action Prompts
**Learning:** Having the exact same installation command displayed twice in the same detail view creates visual clutter and confuses the user about the primary action. The command should be prominently displayed once at the very end of the information block to bridge the gap between discovery and execution.
**Action:** Remove duplicate output of the `winget install` command within the `Show-WingetPackageDetails` function, retaining only the explicit 'Command' section at the bottom.
