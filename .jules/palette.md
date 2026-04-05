## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.

## 2025-05-19 - Do not duplicate actionable commands in detail views
**Learning:** Having the exact same copy-pasteable installation command in multiple places within a single package detail view creates unnecessary visual noise without adding functional value, contrary to the goal of bridging discovery and execution cleanly.
**Action:** Always ensure that designated "Command" or "Usage" sections are displayed exactly once per item, typically at the bottom of the output to serve as a clear call-to-action.