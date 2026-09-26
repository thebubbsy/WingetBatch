function Update-WingetBatch {
    <#
    .SYNOPSIS
        Updates the WingetBatch module from the PowerShell Gallery.
    #>
    [CmdletBinding()]
    param()
    Write-Host "Checking for updates to WingetBatch module..." -ForegroundColor Cyan
    $before = (Get-Module WingetBatch).Version
    Install-WingetBatchDependency -Name WingetBatch -Update
    $after = (Get-Module -ListAvailable WingetBatch | Sort-Object Version -Descending | Select-Object -First 1).Version
    if ($after -le $before) {
        Write-Host "WingetBatch is already up to date (v$before)." -ForegroundColor Green
        return
    }
    Write-Host "Installed v$after. Run 'Import-Module WingetBatch -Force' or open a new terminal to use it." -ForegroundColor Cyan
}

