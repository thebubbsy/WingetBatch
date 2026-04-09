## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.
## 2025-02-18 - Display Package Source Context
**Learning:** Displaying package source context (e.g., `winget` vs `msstore`) using clear, color-coded visual indicators in detail views prevents user confusion and helps them make informed installation decisions.
**Action:** When designing detail views for items originating from multiple repositories, surface the origin prominently with distinct visual styling (emoji + color) to provide immediate context.
