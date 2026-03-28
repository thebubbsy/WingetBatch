## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.
## 2026-03-28 - Remove duplicate action commands to reduce visual clutter
**Learning:** When displaying detailed CLI outputs that include actionable commands (like `winget install`), printing the command multiple times in different sections creates visual clutter and confuses users about the primary call-to-action location.
**Action:** Display actionable commands (e.g., installation, uninstallation) exactly once per item, prominently located at the bottom of the details view, to provide a clear and singular copy-paste target.
