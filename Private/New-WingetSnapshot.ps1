function New-WingetSnapshot {
    <#
    .SYNOPSIS
        Save the current installed-package state to ~/.wingetbatch/snapshots.
        Returns the snapshot as a hashtable.
    #>
    [CmdletBinding()]
    param([string]$Label = 'manual')

    $snapshotDir = Join-Path (Get-WingetBatchConfigDir) "snapshots"
    if (-not (Test-Path $snapshotDir)) {
        New-Item -Path $snapshotDir -ItemType Directory -Force | Out-Null
    }

    # Milliseconds keep IDs unique when an auto-snapshot and a manual one land in the same second
    $id = "snap_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
    $packages = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue)

    $snapshot = [ordered]@{
        Id           = $id
        Timestamp    = (Get-Date).ToString('o')
        Label        = $Label
        Hostname     = $env:COMPUTERNAME
        PackageCount = $packages.Count
        Packages     = @($packages | ForEach-Object {
            [ordered]@{ Id = $_.Id; Name = $_.Name; Version = $_.InstalledVersion; Source = $_.Source }
        })
    }

    $filePath = Join-Path $snapshotDir "$id.json"
    $snapshot | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $filePath -Encoding UTF8
    return $snapshot
}

function Invoke-WingetAutoSnapshot {
    <#
    .SYNOPSIS
        Take a snapshot before a change, if auto-snapshots are enabled
        (Restore-WingetSnapshot -AutoSnapshot $true). Never throws.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Reason)

    try {
        $autoConfigPath = Join-Path (Get-WingetBatchConfigDir) "snapshot_config.json"
        if (-not (Test-Path $autoConfigPath)) { return }
        $autoConfig = Get-Content $autoConfigPath -Raw | ConvertFrom-Json
        if (-not $autoConfig.AutoSnapshot) { return }

        $snap = New-WingetSnapshot -Label "auto: before $Reason"
        Write-Host "  [SNAPSHOT] Saved $($snap.Id) (undo with Restore-WingetSnapshot -UndoLast 1)" -ForegroundColor DarkGray
    }
    catch {
        Write-Verbose "Auto-snapshot skipped: $_"
    }
}
