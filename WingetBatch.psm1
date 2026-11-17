# WingetBatch Module Main
# Dynamically load Public and Private functions

# Windows PowerShell 5.1 defaults SecurityProtocol on older builds to TLS 1.0/1.1; ensure TLS 1.2+
if ($PSVersionTable.PSVersion.Major -lt 6) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
}
else {
    # Ensure UTF-8 console output on PowerShell 7+ so Unicode UI and Spectre Console work without warnings
    try {
        if (-not [Console]::IsOutputRedirected -and [Console]::OutputEncoding.CodePage -ne 65001) {
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            $global:OutputEncoding = $utf8
            [Console]::InputEncoding = $utf8
            [Console]::OutputEncoding = $utf8
        }
    } catch { }
}

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
