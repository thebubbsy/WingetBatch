## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.
## 2026-03-27 - Display Execution Command Once at the End
**Learning:** When designing CLI detail views for packages or resources, displaying the copy-pasteable execution command multiple times causes visual clutter and dilutes the call-to-action.
**Action:** Always include a single, designated 'Command' or 'Usage' section, and place it exactly once at the bottom of the details output to bridge the gap between discovery and execution smoothly.
