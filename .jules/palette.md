## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.

## 2025-05-23 - Improve Information Hierarchy in CLI Package Details
**Learning:** Displaying redundant, copy-pasteable execution commands in multiple places within CLI package details creates visual clutter. Additionally, providing repository context (the source) early on improves scanability and trust.
**Action:** Consolidate redundant commands to a single, designated section at the bottom of the output. Surface critical package metadata like repository source early in the output's "Basic Info" section with clear semantic iconography.