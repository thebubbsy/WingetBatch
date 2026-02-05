
# Mock winget globally so the module sees it
function global:winget {
    param([Parameter(ValueFromRemainingArguments=$true)]$Args)
    Start-Sleep -Milliseconds 100

    # Mock output for search
    if ($Args -contains "search") {
        @"
Name                  Id           Version
------------------------------------------
Visual Studio Code    Microsoft.VSCode 1.90.0
"@
    }
}

# Import the module
Import-Module ./WingetBatch.psm1 -Force

Write-Host "Starting benchmark..."

# Run benchmark
# "visual studio code" -> 3 words -> 3 calls expected in baseline
$time = Measure-Command {
    Install-WingetAll -SearchTerms "visual studio code" -Silent
}

Write-Host "Duration: $($time.TotalMilliseconds) ms"
