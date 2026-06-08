function Test-WingetPackageVibes {
    <#
    .SYNOPSIS
        Analyzes a package's metadata and outputs whether its vibes are Based, Cringe, or Sus.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [string]$Id
    )

    process {
        Write-Host "Scanning $Id for vibes..." -ForegroundColor Magenta
        
        $vowels = ($Id -replace '[^aeiouAEIOU]', '').Length
        $consonants = ($Id -replace '[^a-zA-Z]', '').Length - $vowels
        $score = $vowels * 2 + $consonants

        $vibe = "Unknown"
        $color = "White"

        if ($Id -match "Microsoft|Google|Apple") {
            $vibe = "Corporate (Cringe)"
            $color = "Red"
        }
        elseif ($score % 7 -eq 0) {
            $vibe = "Immaculate"
            $color = "Cyan"
        }
        elseif ($score % 3 -eq 0) {
            $vibe = "Based"
            $color = "Green"
        }
        elseif ($score % 2 -eq 0) {
            $vibe = "Sus"
            $color = "Yellow"
        }
        else {
            $vibe = "Mid"
            $color = "DarkGray"
        }

        Write-Host "Vibe Check Result: " -NoNewline
        Write-Host $vibe -ForegroundColor $color
    }
}