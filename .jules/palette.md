## 2025-11-04 - Remove Duplicate Command & Show Release Notes
**Learning:** Found that `winget install` command was rendered twice, breaking focus and scanability, while useful parsed information like `ReleaseNotes` was missing from the output completely. Also discovered that `⚖️` had an extra trailing space causing visual misalignment.
**Action:** Replaced duplicate `Command` section with missing `Release Notes` section and removed trailing space in the `⚖️` emoji string to fix padding calculations.
