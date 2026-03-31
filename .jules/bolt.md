## 2025-10-27 - [PowerShell Array Concatenation Anti-Pattern]
**Learning:** The codebase explicitly claims to prioritize `System.Collections.Generic.List` over `+=`, but `Install-WingetAll` (the main function) was using `+=` inside nested loops, causing potential O(N^2) behavior on large search results.
**Action:** Always verify "known" architectural patterns against actual code. When using `List<T>.AddRange()` in PowerShell, always wrap the argument in `@(...)` to safely handle both scalars and arrays.

## 2026-02-06 - [Parallel File I/O Race Condition]
**Learning:** `Start-Job` processes run independently. If they all write to the same cache file (even with `test-path` checks), they will overwrite each other, causing data loss or corruption. Also, `ConvertTo-Json` fails if Hashtable keys are not explicitly strings.
**Action:** Move all file I/O to the main thread. Have jobs return data, and let the main thread aggregate and save once. Cast Hashtable keys to `[string]` before `ConvertTo-Json`.

## 2026-02-14 - [Process vs Thread Job Overhead]
**Learning:** `Start-Job` creates a new PowerShell process for each job, incurring significant startup overhead (~140ms per job on typical hardware). When spawning many jobs (e.g., 50-100), this results in seconds of delay just for job creation. `Start-ThreadJob` runs in a thread within the current process, with startup overhead of ~6ms (22x faster).
**Action:** Use `Start-ThreadJob` for background tasks, especially when launching multiple concurrent tasks or small tasks where process startup time dominates. Ensure a fallback to `Start-Job` is available if `ThreadJob` module is missing (e.g. on older Windows PowerShell without the module installed).

## 2026-02-14 - [Double Iteration with Regex Overhead]
**Learning:** `Install-WingetAll` iterated over `$foundPackages` twice: once to build a display list and again to build a lookup map. Both loops performed identical, expensive `ConvertTo-SpectreEscaped` (regex replacement) operations.
**Action:** Consolidate such loops into a single pass. Build multiple data structures simultaneously to avoid redundant iterations and re-calculations.

## 2025-11-05 - [PowerShell Group-Object Anti-Pattern]
**Learning:** `Group-Object` in PowerShell has significant overhead and exhibits O(N) performance for deduplication because it builds full group structures and properties. When using it simply to find unique items or group them for display, it adds substantial latency to array processing. Using a `System.Collections.Generic.HashSet[string]` for deduplication, or a native PowerShell Hashtable (`@{}`) for grouping, is substantially faster (reducing deduplication time from ~266ms to ~34ms for 2500 items).
**Action:** Replace `Group-Object` in critical paths with `HashSet[string]` for distinct elements and Hashtables mapping keys to `System.Collections.Generic.List[T]` for grouping collections.

## 2025-11-05 - [Regex Overhead in Nested Loops]
**Learning:** Using regex pattern matching (e.g., `-notmatch`) inside tight nested loops for simple substring matching incurs significant overhead. In PowerShell, `String.IndexOf(..., [System.StringComparison]::OrdinalIgnoreCase)` is significantly faster (over 50% reduction in execution time in benchmarks) than `-match` or `-notmatch` for case-insensitive substring search because it bypasses regex compilation and evaluation entirely.
**Action:** Replace `-match` and `-notmatch` with `.IndexOf(...)` or `.Contains(...)` when doing simple substring checks within large loops, especially when the search term is plain text and doesn't require regex features.

## 2026-03-31 - [Regex Overhead in String Literal Substitution]
**Learning:** Using `-replace` for simple string literal substitutions incurs significant regex compilation and evaluation overhead. Combining `.Replace()` with an early exit check using `.IndexOf()` significantly improves performance by avoiding unnecessary string allocations and regex overhead.
**Action:** Use `.IndexOf()` and `.Replace()` instead of `-replace` for simple string literal escaping, especially in frequently called functions like `ConvertTo-SpectreEscaped`.
