## 2025-05-02 - [PowerShell String Processing Optimization]
**Learning:** `Out-String` in PowerShell adds significant overhead when processing arrays of strings (like native command output) because it joins them into a single string, often requiring a subsequent split operation.
**Action:** When processing output from native commands (like `winget`), handle the array of strings directly instead of piping to `Out-String`. If a function must accept both, use `[object]` or `[string[]]` and detect the type. For string splitting, `.Split([char[]]@("`n", "`r"), ...)` is ~4x faster than `-split`.
