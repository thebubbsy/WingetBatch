function Update-WingetBatch {
    <#
    .SYNOPSIS
        Updates the WingetBatch module from the PowerShell Gallery.
    #>
    [CmdletBinding()]
    param()
    Write-Host "Checking for updates to WingetBatch module..." -ForegroundColor Cyan
    Update-Module -Name WingetBatch -Force -AcceptLicense -ErrorAction Stop
    Write-Host "WingetBatch module updated successfully!" -ForegroundColor Green
}

