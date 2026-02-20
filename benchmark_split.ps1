
$text = "Line 1`nLine 2`nLine 3`n" * 1000

Write-Host "Benchmarking string splitting (3000 lines)..."

$sw1 = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 1000; $i++) {
    $null = $text -split "`n"
}
$sw1.Stop()
Write-Host "-split took: $($sw1.ElapsedMilliseconds) ms"

$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
$separators = [char[]]@("`n", "`r")
for ($i = 0; $i -lt 1000; $i++) {
    $null = $text.Split($separators, [System.StringSplitOptions]::RemoveEmptyEntries)
}
$sw2.Stop()
Write-Host ".Split() took: $($sw2.ElapsedMilliseconds) ms"
