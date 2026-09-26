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

    if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
        return Start-ThreadJob -Name 'WingetBatchDetails' -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
    else {
        return Start-Job -Name 'WingetBatchDetails' -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
}
