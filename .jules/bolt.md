## 2025-10-27 - [PowerShell Array Concatenation Anti-Pattern]
**Learning:** The codebase explicitly claims to prioritize `System.Collections.Generic.List` over `+=`, but `Install-WingetAll` (the main function) was using `+=` inside nested loops, causing potential O(N^2) behavior on large search results.
**Action:** Always verify "known" architectural patterns against actual code. When using `List<T>.AddRange()` in PowerShell, always wrap the argument in `@(...)` to safely handle both scalars and arrays.
