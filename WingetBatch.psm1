# WingetBatch Module Main
# Dynamically load Public and Private functions

# Load Private functions (Internal helpers)
$privateDir = Join-Path $PSScriptRoot "Private"
if (Test-Path $privateDir) {
    Get-ChildItem -Path $privateDir -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

# Load Public functions (User-facing cmdlets)
$publicDir = Join-Path $PSScriptRoot "Public"
if (Test-Path $publicDir) {
    Get-ChildItem -Path $publicDir -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

# Export public functions
Export-ModuleMember -Function (Get-ChildItem -Path $publicDir -Filter "*.ps1").BaseName
