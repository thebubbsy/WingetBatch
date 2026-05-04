$content = Get-Content Public\Get-WingetNewPackages.ps1 -Raw
$content = $content -replace " `\r?\n", "`n"
Set-Content Public\Get-WingetNewPackages.ps1 $content -Encoding UTF8
$content2 = Get-Content Public\Get-WingetUpdates.ps1 -Raw
$content2 = $content2 -replace " `\r?\n", "`n"
Set-Content Public\Get-WingetUpdates.ps1 $content2 -Encoding UTF8
