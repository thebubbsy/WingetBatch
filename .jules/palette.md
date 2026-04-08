## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.

## 2024-05-18 - Avoid duplicating functional elements in package details
**Learning:** Displaying copy-pasteable commands multiple times in a single details view creates visual clutter and confusion. Designated execution commands bridge the gap between discovery and execution, but they only need to be displayed once, typically at the end.
**Action:** When designing CLI detail views for packages or resources, always include a designated copy-pasteable 'Command' or 'Usage' section, but display it only once (typically at the end) to avoid visual clutter.