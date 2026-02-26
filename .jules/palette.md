## 2025-11-20 - [Manifest for Batch Actions]
**Learning:** Users lack confidence in batch CLI operations when the action starts immediately after selection. A "Manifest" or "Summary Table" before execution provides crucial confirmation and reduces anxiety, even if it's not interactive.
**Action:** Always display a summary of affected items before executing batch operations in CLI tools.

## 2025-11-21 - [Emoji Scanability in CLI]
**Learning:** Adding semantic emojis (e.g., 🏢 for Publisher, ⚖️ for License) to detailed CLI output significantly improves scanability and helps users quickly locate specific metadata fields without reading labels.
**Action:** Use consistent emojis as visual anchors for key metadata fields in detailed views.

## 2026-02-12 - [Visual Hierarchy in CLI Output]
**Learning:** Flat lists of metadata are hard to scan. Grouping related fields (Basic, Publisher, Tech, Links) with visual spacers creates a clear hierarchy that guides the user's eye and reduces cognitive load.
**Action:** Use logical grouping and spacing when displaying dense information in terminal interfaces.

## 2026-02-13 - [Information Priority in CLI]
**Learning:** Users need immediate context about "what is this?" before "what version is this?". Prioritizing the Description field at the top of the detailed view significantly reduces cognitive load and confirms selection faster.
**Action:** Always place the Description or Summary field immediately after the Item Header, before secondary metadata like Version or Publisher.

## 2026-02-14 - [Actionable CLI Context]
**Learning:** Displaying the exact CLI command to replicate an action (e.g., `winget install --id "ID"`) reduces friction for users who need to share instructions or automate tasks later.
**Action:** Always include a copy-paste friendly "Command" section in detailed package views for CLI tools.
