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

# Register argument completers (tab-completion for package IDs)
try {
    Register-WingetBatchCompleters
} catch {
    # Non-critical: completers are a nice-to-have
}

# Module import banner (only in interactive sessions)
if ([Environment]::UserInteractive -and -not [Console]::IsOutputRedirected) {
    $moduleVersion = (Get-Module -Name WingetBatch -ErrorAction SilentlyContinue).Version
    if (-not $moduleVersion) {
        $manifestPath = Join-Path $PSScriptRoot "WingetBatch.psd1"
        if (Test-Path $manifestPath) {
            $manifest = Import-PowerShellDataFile $manifestPath -ErrorAction SilentlyContinue
            $moduleVersion = $manifest.ModuleVersion
        }
    }
}
