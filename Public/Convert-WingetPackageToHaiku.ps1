function Convert-WingetPackageToHaiku {
    <#
    .SYNOPSIS
        Generates a poetic 5-7-5 syllable Haiku about a Winget package.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [string]$Id
    )

    process {
        # Determine some arbitrary traits based on the package ID
        $parts = $Id -split '\.'
        $publisher = if ($parts.Count -gt 0) { $parts[0] } else { "Unknown" }
        $app = if ($parts.Count -gt 1) { $parts[1] } else { $Id }

        $line1 = @(
            "Software from $publisher",
            "Code of $publisher",
            "A gift from $publisher",
            "Bits from $publisher"
        ) | Get-Random

        $line2 = @(
            "Downloading $app now",
            "Updating $app soon",
            "$app comes to my disk",
            "Wait for $app to run"
        ) | Get-Random

        $line3 = @(
            "Exit code zero.",
            "Reboot required now.",
            "Install is complete.",
            "Cache is full of bytes."
        ) | Get-Random

        Write-Host "`n  $line1" -ForegroundColor Cyan
        Write-Host "  $line2" -ForegroundColor Cyan
        Write-Host "  $line3`n" -ForegroundColor Cyan
    }
}