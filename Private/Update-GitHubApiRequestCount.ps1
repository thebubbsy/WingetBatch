function Update-GitHubApiRequestCount {
    <#
    .SYNOPSIS
        Track GitHub API requests per hour.

    .DESCRIPTION
        Internal function to track and display GitHub API request usage.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$RequestCount = 1
    )

    $configDir = Get-WingetBatchConfigDir
    $rateLimitFile = Join-Path $configDir "github_ratelimit.json"

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $now = Get-Date

    # Load or create rate limit tracking data
    if (Test-Path $rateLimitFile) {
        try {
            $jsonData = Get-Content $rateLimitFile -Raw | ConvertFrom-Json
            $lastReset = [DateTime]$jsonData.LastReset

            # Reset counter if more than 1 hour has passed
            if (($now - $lastReset).TotalHours -ge 1) {
                $rateLimitData = @{
                    RequestCount = $RequestCount
                    LastReset = $now.ToString('o')
                }
            }
            else {
                # Accumulate requests - ensure we're working with integers
                $currentCount = [int]$jsonData.RequestCount
                $rateLimitData = @{
                    RequestCount = $currentCount + $RequestCount
                    LastReset = $jsonData.LastReset
                }
            }
        }
        catch {
            # If file is corrupt, create new
            $rateLimitData = @{
                RequestCount = $RequestCount
                LastReset = $now.ToString('o')
            }
        }
    }
    else {
        $rateLimitData = @{
            RequestCount = $RequestCount
            LastReset = $now.ToString('o')
        }
    }

    # Save updated data - ensure JSON is written properly
    $jsonContent = $rateLimitData | ConvertTo-Json -Compress:$false
    [System.IO.File]::WriteAllText($rateLimitFile, $jsonContent, [System.Text.Encoding]::UTF8)

    return [PSCustomObject]$rateLimitData
}
