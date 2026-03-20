## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.
## 2024-05-20 - Remove duplicate actionable commands to reduce visual clutter
**Learning:** When adding a prominent "Command" or "Usage" section to a CLI details view to make it easily copy-pasteable, displaying it multiple times (e.g., both mid-content and at the end) creates unnecessary visual clutter and detracts from the designated "actionable" area.
**Action:** Ensure designated copy-pasteable commands are displayed only once, ideally at the end of the detail view, bridging discovery and execution cleanly without redundancy.
