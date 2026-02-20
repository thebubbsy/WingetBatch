
# Mock winget output (array of strings)
$mockOutputArray = 1..100 | ForEach-Object { "Line $($_): Value $_" }
$mockOutputString = $mockOutputArray -join "`n"

function Parse-Original {
    param([string]$Output)
    $lines = $Output -split "`n"
    return $lines.Count
}

function Parse-Optimized {
    param([object]$Output)

    if ($Output -is [string]) {
        $lines = $Output.Split([char[]]@("`n", "`r"), [System.StringSplitOptions]::RemoveEmptyEntries)
    } elseif ($Output -is [System.Collections.IEnumerable] -and $Output -isnot [string]) {
        $lines = $Output
    } else {
        $lines = @($Output)
    }

    return $lines.Count
}

Write-Host "Benchmarking Parsing (10,000 iterations)..."

# Scenario 1: Original (pass string, split inside)
$sw1 = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 10000; $i++) {
    $null = Parse-Original -Output $mockOutputString
}
$sw1.Stop()
Write-Host "Original (String input): $($sw1.ElapsedMilliseconds) ms"

# Scenario 2: Optimized (pass array directly)
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 10000; $i++) {
    $null = Parse-Optimized -Output $mockOutputArray
}
$sw2.Stop()
Write-Host "Optimized (Array input): $($sw2.ElapsedMilliseconds) ms"

# Scenario 3: Optimized (pass string, split efficiently)
$sw3 = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 10000; $i++) {
    $null = Parse-Optimized -Output $mockOutputString
}
$sw3.Stop()
Write-Host "Optimized (String input): $($sw3.ElapsedMilliseconds) ms"
