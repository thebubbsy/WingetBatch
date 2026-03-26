## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.

## 2025-11-03 - Remove duplicate command output to prevent visual clutter
**Learning:** Having the exact same block of information (like a command to run) appear multiple times in a single detail view causes visual clutter and can confuse the user about where to look. In `Show-WingetPackageDetails`, the command was shown in the middle of the output and again at the end.
**Action:** Consolidate designated "Command" or "Usage" sections to appear exactly once, typically at the end of a details output, to bridge the gap between discovery and execution without redundancy.