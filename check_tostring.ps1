
function Parse-Test {
    param([object]$Output)
    foreach ($item in $Output) {
        $line = "$item"
        Write-Host "Processed: $line (Type: $($item.GetType().Name))"
    }
}

$output = ls -z 2>&1
Parse-Test -Output $output
