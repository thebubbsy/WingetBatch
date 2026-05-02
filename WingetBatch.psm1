# WingetBatch Module Main
# Dynamically load Public and Private functions

$publicDir = Join-Path $PSScriptRoot "Public"
$privateDir = Join-Path $PSScriptRoot "Private"

if (Test-Path $privateDir) {
    Get-ChildItem -Path $privateDir -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

if (Test-Path $publicDir) {
    Get-ChildItem -Path $publicDir -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

# Export public functions
Export-ModuleMember -Function (Get-ChildItem -Path $publicDir -Filter "*.ps1").BaseName
