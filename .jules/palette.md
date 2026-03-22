## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.
## 2025-02-12 - Remove Duplicate Command Display in CLI Details
**Learning:** Displaying actionable installation commands multiple times in a single CLI detail view creates visual clutter and dilutes the call to action.
**Action:** When designing CLI detail views for packages or resources, always include a designated copy-pasteable 'Command' or 'Usage' section, but display this command exactly once (typically at the end) to bridge the gap between discovery and execution without confusion.

## 2025-02-12 - Surface Package Source in Basic Info
**Learning:** Critical context about the package repository (e.g., winget vs msstore) is frequently missed if relegated to secondary sections or link lists.
**Action:** When designing CLI detail views for packages, surface the package 'Source' in the primary 'Basic Info' section using a distinct icon (like 💾) to immediately inform users about the origin of the installation.
