## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.
## 2026-03-21 - Ensure consistent keyboard shortcut hints for multi-selection prompts
**Learning:** Keyboard shortcut hints (like `(Space to toggle, Enter to confirm)`) were inconsistently applied across multi-selection prompts, reducing accessibility and discoverability for users primarily navigating via keyboard.
**Action:** Always include explicit, uniform keyboard shortcut instructions in the title of `Read-SpectreMultiSelection` prompts to bridge the gap between UI elements and keyboard interactions.

## 2026-03-21 - Package Source context is critical for installation decisions
**Learning:** When users select a package for installation, knowing the package repository (e.g., `winget` vs `msstore`) is critical context that helps them understand how the app will be installed and updated. Hiding this information in detailed views degrades the UX.
**Action:** Always surface the repository/source alongside other basic package information (like Version) in detailed views, using the standard `💾 (Source)` semantic emoji.
