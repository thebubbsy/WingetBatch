$moduleDir = $PSScriptRoot
$standaloneFile = Join-Path $moduleDir "WingetBatch_Standalone.ps1"

Write-Host "Building WingetBatch_Standalone.ps1..." -ForegroundColor Cyan

$content = @"
<#
.SYNOPSIS
    WingetBatch Standalone Script
    
.DESCRIPTION
    This is an automatically generated standalone script containing all the functions
    from the WingetBatch module. You can dot-source this script directly if you don't
    want to install the module.
#>

"@

# Add Private functions
Write-Host "Adding Private functions..." -ForegroundColor Gray
$privateFiles = Get-ChildItem -Path (Join-Path $moduleDir "Private") -Filter "*.ps1" | Sort-Object Name
foreach ($file in $privateFiles) {
    $content += "`n# Region: Private/$($file.Name)`n"
    $content += Get-Content $file.FullName -Raw
    $content += "`n# EndRegion`n"
}

# Add Public functions
Write-Host "Adding Public functions..." -ForegroundColor Gray
$publicFiles = Get-ChildItem -Path (Join-Path $moduleDir "Public") -Filter "*.ps1" | Sort-Object Name
foreach ($file in $publicFiles) {
    $content += "`n# Region: Public/$($file.Name)`n"
    $content += Get-Content $file.FullName -Raw
    $content += "`n# EndRegion`n"
}

Set-Content -Path $standaloneFile -Value $content -Encoding UTF8
Write-Host "Build complete: WingetBatch_Standalone.ps1" -ForegroundColor Green
