## 2025-11-20 - [PowerShell String Processing Anti-Pattern]
**Learning:** Avoid manually accumulating external command output (like `winget`) into a `List[string]` and then joining/splitting it. PowerShell automatically streams command output as an array of strings.
**Action:** Use direct assignment `$lines = @(command)` instead of manual accumulation loops for external command output.
