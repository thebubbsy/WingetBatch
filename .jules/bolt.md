## 2025-10-27 - [PowerShell Array Concatenation Anti-Pattern]
**Learning:** The codebase explicitly claims to prioritize `System.Collections.Generic.List` over `+=`, but `Install-WingetAll` (the main function) was using `+=` inside nested loops, causing potential O(N^2) behavior on large search results.
**Action:** Always verify "known" architectural patterns against actual code. When using `List<T>.AddRange()` in PowerShell, always wrap the argument in `@(...)` to safely handle both scalars and arrays.

## 2026-02-06 - [Parallel File I/O Race Condition]
**Learning:** `Start-Job` processes run independently. If they all write to the same cache file (even with `test-path` checks), they will overwrite each other, causing data loss or corruption. Also, `ConvertTo-Json` fails if Hashtable keys are not explicitly strings.
**Action:** Move all file I/O to the main thread. Have jobs return data, and let the main thread aggregate and save once. Cast Hashtable keys to `[string]` before `ConvertTo-Json`.
