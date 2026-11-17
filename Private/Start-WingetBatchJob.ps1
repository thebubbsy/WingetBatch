function Start-WingetBatchJob {
    <#
    .SYNOPSIS
        Internal helper to start a job using Start-ThreadJob if available, otherwise Start-Job.
    #>
    [CmdletBinding()]
    param(
        [ScriptBlock]$ScriptBlock,
        [Object[]]$ArgumentList
    )

    $threadJobReady = $false
    $threadJobCmd = Get-Command -Name 'Start-ThreadJob' -ErrorAction SilentlyContinue
    if ($threadJobCmd) {
        if ($threadJobCmd.CommandType -eq 'Function' -or $null -ne $threadJobCmd.Module -or (Get-Module -Name 'Microsoft.PowerShell.ThreadJob', 'ThreadJob' -ErrorAction SilentlyContinue)) {
            $threadJobReady = $true
        }
    }

    if (-not $threadJobReady) {
        $candidates = @()
        if ($PSVersionTable.PSEdition -eq 'Core') {
            foreach ($rel in @('Modules\Microsoft.PowerShell.ThreadJob', 'Modules\ThreadJob')) {
                $builtInPath = Join-Path -Path $PSHOME -ChildPath $rel
                if (Test-Path -LiteralPath $builtInPath) {
                    $candidates += $builtInPath
                }
            }
        }
        $candidates += @(Get-Module -ListAvailable -Name 'Microsoft.PowerShell.ThreadJob', 'ThreadJob' -ErrorAction SilentlyContinue | ForEach-Object { $_.Path })
        foreach ($candidatePath in ($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
            try {
                Import-Module -Name $candidatePath -Global -ErrorAction Stop | Out-Null
                $loadedCmd = Get-Command -Name 'Start-ThreadJob' -ErrorAction SilentlyContinue
                if ($loadedCmd -and ($null -ne $loadedCmd.Module -or (Get-Module -Name 'Microsoft.PowerShell.ThreadJob', 'ThreadJob' -ErrorAction SilentlyContinue))) {
                    $threadJobReady = $true
                    break
                }
            }
            catch {
                Write-Verbose "Skipping ThreadJob candidate '$candidatePath': $($_.Exception.Message)"
            }
        }
    }

    if ($threadJobReady) {
        return Start-ThreadJob -Name 'WingetBatchDetails' -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
    else {
        return Start-Job -Name 'WingetBatchDetails' -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
}
