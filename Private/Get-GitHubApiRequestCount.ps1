function Get-GitHubApiRequestCount {
    <#
    .SYNOPSIS
        Get current GitHub API request count for this hour.

    .DESCRIPTION
        Returns the number of GitHub API requests made in the current hour.
    #>

    [CmdletBinding()]
    param()

    $rateLimitFile = Join-Path (Get-WingetBatchConfigDir) "github_ratelimit.json"

    if (Test-Path $rateLimitFile) {
        try {
            $rateLimitData = Get-Content $rateLimitFile -Raw | ConvertFrom-Json
            $lastReset = [DateTime]$rateLimitData.LastReset
            $now = Get-Date

            # If more than 1 hour has passed, return 0
            if (($now - $lastReset).TotalHours -ge 1) {
                return 0
            }

            return [int]$rateLimitData.RequestCount
        }
        catch {
            return 0
        }
    }

    return 0
}
