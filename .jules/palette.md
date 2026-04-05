## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.

## 2025-11-04 - Remove duplicate installation command
**Learning:** When designing CLI detail views for packages or resources, it is important to include a designated copy-pasteable 'Command' or 'Usage' section to bridge the gap between discovery and execution. However, displaying this command multiple times causes visual clutter and confusion.
**Action:** Always include a designated copy-pasteable 'Command' or 'Usage' section (e.g., `winget install --id "Pkg.Id" -e`) only once (typically at the end) to avoid visual clutter.