function Read-WingetConsoleSelection {
    <#
    .SYNOPSIS
        Interactive numbered console prompt used when PwshSpectreConsole is unavailable.

    .DESCRIPTION
        Displays numbered choices and accepts single selections, comma/space lists,
        numeric ranges (e.g. 1-3), 'all', or empty input to cancel.
        Returns selected 0-based indices (with -ReturnIndex) or choice strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string[]]$Choices,

        [switch]$MultiSelect,

        [switch]$ReturnIndex
    )

    if (-not $Choices -or $Choices.Count -eq 0) {
        return @()
    }

    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $Choices.Count; $i++) {
        Write-Host ("  [{0}] " -f ($i + 1)) -ForegroundColor Cyan -NoNewline
        Write-Host $Choices[$i] -ForegroundColor White
    }
    Write-Host ""

    $selectedIndices = [System.Collections.Generic.List[int]]::new()
    $seen = [System.Collections.Generic.HashSet[int]]::new()

    while ($true) {
        $prompt = if ($MultiSelect) {
            if ($Choices.Count -eq 1) {
                "  Enter 1 (or 'y') to select, or Enter to cancel"
            }
            else {
                "  Enter numbers (e.g. 1, 1-3, 'all', or Enter to cancel)"
            }
        }
        else {
            "  Enter number (1-$($Choices.Count), or Enter to cancel)"
        }

        $answer = Read-Host $prompt
        if ($null -eq $answer) {
            break
        }
        $trimmed = $answer.Trim()
        if ($trimmed -eq '' -or $trimmed -match '^(q|quit|cancel|n|no|none)$') {
            break
        }

        $selectedIndices.Clear()
        $seen.Clear()
        $invalid = $false

        if ($MultiSelect -and $trimmed -match '^(a|all|\*)$') {
            for ($i = 0; $i -lt $Choices.Count; $i++) {
                if ($seen.Add($i)) { $selectedIndices.Add($i) }
            }
            break
        }
        elseif ($Choices.Count -eq 1 -and $trimmed -match '^(y|yes)$') {
            $selectedIndices.Add(0)
            break
        }

        $tokens = $trimmed -split '[,\s]+' | Where-Object { $_ -ne '' }
        foreach ($tok in $tokens) {
            if ($MultiSelect -and $tok -match '^(\d+)-(\d+)$') {
                $start = [int]$Matches[1]
                $end = [int]$Matches[2]
                if ($start -lt 1 -or $end -lt 1 -or $start -gt $Choices.Count -or $end -gt $Choices.Count) {
                    $invalid = $true
                    break
                }
                $step = if ($start -le $end) { 1 } else { -1 }
                for ($n = $start; ($step -gt 0 -and $n -le $end) -or ($step -lt 0 -and $n -ge $end); $n += $step) {
                    $idx = $n - 1
                    if ($seen.Add($idx)) { $selectedIndices.Add($idx) }
                }
            }
            elseif ($tok -match '^\d+$') {
                $n = [int]$tok
                if ($n -lt 1 -or $n -gt $Choices.Count) {
                    $invalid = $true
                    break
                }
                $idx = $n - 1
                if ($seen.Add($idx)) { $selectedIndices.Add($idx) }
                if (-not $MultiSelect) { break }
            }
            else {
                $invalid = $true
                break
            }
        }

        if (-not $invalid -and $selectedIndices.Count -gt 0) {
            break
        }

        Write-Host "  Invalid selection. Choose between 1 and $($Choices.Count), or press Enter to cancel." -ForegroundColor Yellow
    }

    if ($ReturnIndex) {
        return $selectedIndices.ToArray()
    }

    $result = @($selectedIndices | ForEach-Object { $Choices[$_] })
    if (-not $MultiSelect) {
        if ($result.Count -gt 0) { return $result[0] }
        return $null
    }
    return $result
}
