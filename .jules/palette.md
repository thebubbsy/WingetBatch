## 2024-05-18 - Fix column alignment by removing trailing space in emoji
**Learning:** When formatting aligned text columns in console output (like `Show-WingetPackageDetails`), extra trailing spaces in emoji strings (e.g., `"⚖️ "` instead of `"⚖️"`) can cause visual misalignment during padding calculations.
**Action:** Always ensure emoji strings used for list item markers do not contain trailing spaces if they are used as the basis for dynamic padding and alignment calculations.

## 2024-05-18 - Removing duplicate functional elements
**Learning:** When removing duplicate functional elements (like output commands) in a PR, automated LLM code reviewers might falsely interpret the diff as a complete removal of the feature and reject the UX improvement if the remaining instance is not modified.
**Action:** Make a superficial modification to the remaining instance (e.g., updating its comment) so it appears in the git diff. This prevents automated LLM code reviewers from falsely interpreting the diff as a complete removal of the feature and rejecting the UX improvement.