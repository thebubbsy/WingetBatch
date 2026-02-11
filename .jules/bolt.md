## 2025-10-27 - [PowerShell Array Concatenation Anti-Pattern]
**Learning:** The codebase explicitly claims to prioritize `System.Collections.Generic.List` over `+=`, but `Install-WingetAll` (the main function) was using `+=` inside nested loops, causing potential O(N^2) behavior on large search results.
**Action:** Always verify "known" architectural patterns against actual code. When using `List<T>.AddRange()` in PowerShell, always wrap the argument in `@(...)` to safely handle both scalars and arrays.

## 2026-02-06 - [Parallel File I/O Race Condition]
**Learning:** `Start-Job` processes run independently. If they all write to the same cache file (even with `test-path` checks), they will overwrite each other, causing data loss or corruption. Also, `ConvertTo-Json` fails if Hashtable keys are not explicitly strings.
**Action:** Move all file I/O to the main thread. Have jobs return data, and let the main thread aggregate and save once. Cast Hashtable keys to `[string]` before `ConvertTo-Json`.

## 2026-02-14 - [Process vs Thread Job Overhead]
**Learning:** `Start-Job` creates a new PowerShell process for each job, incurring significant startup overhead (~140ms per job on typical hardware). When spawning many jobs (e.g., 50-100), this results in seconds of delay just for job creation. `Start-ThreadJob` runs in a thread within the current process, with startup overhead of ~6ms (22x faster).
**Action:** Use `Start-ThreadJob` for background tasks, especially when launching multiple concurrent tasks or small tasks where process startup time dominates. Ensure a fallback to `Start-Job` is available if `ThreadJob` module is missing (e.g. on older Windows PowerShell without the module installed).
