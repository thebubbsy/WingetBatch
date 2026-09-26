function Restore-WingetSnapshot {
    <#
    .SYNOPSIS
        Package-level rollback: undo installs, updates, and uninstalls.

    .DESCRIPTION
        Maintains a timeline of package state snapshots and enables rollback
        to any previous point. Snapshots are taken manually (-Take) or automatically
        before every WingetBatch install/update/uninstall once -AutoSnapshot $true is set.

        A rollback reinstalls packages removed since the snapshot (at the snapshot's
        version) and uninstalls WinGet-sourced packages added since. With
        -RestoreVersions it also moves updated packages back to their snapshot version.
        Programs without a WinGet source are never uninstalled.

    .PARAMETER Take
        Capture a snapshot of the current package state right now.

    .PARAMETER Label
        Human-readable label for the snapshot (e.g., "before-vscode-update").

    .PARAMETER List
        Show all available snapshots with timestamps and labels.

    .PARAMETER Restore
        Roll back to a specific snapshot (use with -SnapshotId).

    .PARAMETER UndoLast
        Roll back to the Nth most recent snapshot. With auto-snapshots on,
        -UndoLast 1 undoes the most recent WingetBatch operation.

    .PARAMETER Since
        Restore to the latest snapshot taken at or before this date/time.

    .PARAMETER Diff
        Show what changed since a snapshot (the most recent one by default).

    .PARAMETER SnapshotId
        Target snapshot identifier for Restore operations.

    .PARAMETER DiffSnapshotId
        Snapshot to compare against for -Diff.

    .PARAMETER RestoreVersions
        Also install the snapshot's version of packages that were updated or downgraded since.

    .PARAMETER Force
        Skip the confirmation prompt.

    .PARAMETER PruneOld
        Remove snapshots older than N days.

    .PARAMETER AutoSnapshot
        Enable or disable automatic snapshots before every install/uninstall/update.

    .EXAMPLE
        Restore-WingetSnapshot -Take -Label "before-big-update"
        Manually captures current state with a label.

    .EXAMPLE
        Restore-WingetSnapshot -List
        Shows all snapshots: ID, date, label, package count.

    .EXAMPLE
        Restore-WingetSnapshot -UndoLast 1 -RestoreVersions
        Rolls back to the most recent snapshot, including version changes.

    .EXAMPLE
        Restore-WingetSnapshot -Since "2025-01-15"
        Restores to the state as of January 15th.

    .EXAMPLE
        Restore-WingetSnapshot -Diff -DiffSnapshotId "snap_20250115_143022"
        Shows what changed since that snapshot.

    .NOTES
        Author: Matthew Bubb
        Snapshots stored in ~/.wingetbatch/snapshots/ as JSON.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Take')]
    param(
        [Parameter(ParameterSetName = 'Take')]
        [switch]$Take,

        [Parameter(ParameterSetName = 'Take')]
        [string]$Label,

        [Parameter(ParameterSetName = 'List', Mandatory)]
        [switch]$List,

        [Parameter(ParameterSetName = 'Restore', Mandatory)]
        [switch]$Restore,

        [Parameter(ParameterSetName = 'Restore', Mandatory)]
        [string]$SnapshotId,

        [Parameter(ParameterSetName = 'Undo', Mandatory)]
        [ValidateRange(1, 1000)]
        [int]$UndoLast,

        [Parameter(ParameterSetName = 'Since', Mandatory)]
        [datetime]$Since,

        [Parameter(ParameterSetName = 'Restore')]
        [Parameter(ParameterSetName = 'Undo')]
        [Parameter(ParameterSetName = 'Since')]
        [switch]$RestoreVersions,

        [Parameter(ParameterSetName = 'Restore')]
        [Parameter(ParameterSetName = 'Undo')]
        [Parameter(ParameterSetName = 'Since')]
        [switch]$Force,

        [Parameter(ParameterSetName = 'Diff', Mandatory)]
        [switch]$Diff,

        [Parameter(ParameterSetName = 'Diff')]
        [string]$DiffSnapshotId,

        [Parameter(ParameterSetName = 'Prune', Mandatory)]
        [ValidateRange(1, 3650)]
        [int]$PruneOld,

        [Parameter(ParameterSetName = 'Auto', Mandatory)]
        [bool]$AutoSnapshot
    )

    # --- Snapshot storage ---
    $configDir = Get-WingetBatchConfigDir
    $snapshotDir = Join-Path $configDir "snapshots"
    if (-not (Test-Path $snapshotDir)) {
        New-Item -Path $snapshotDir -ItemType Directory -Force | Out-Null
    }
    $autoConfigPath = Join-Path $configDir "snapshot_config.json"

    # --- Helper: Load snapshot ---
    function Get-SnapshotFile {
        param([string]$Id)
        $path = Join-Path $snapshotDir "$Id.json"
        if (Test-Path $path) {
            return (Get-Content $path -Raw | ConvertFrom-Json)
        }
        return $null
    }

    # --- Helper: All snapshots, newest first ---
    function Get-AllSnapshots {
        $all = foreach ($file in (Get-ChildItem -Path $snapshotDir -Filter "snap_*.json" -ErrorAction SilentlyContinue)) {
            try { Get-Content $file.FullName -Raw | ConvertFrom-Json } catch { }
        }
        @($all | Sort-Object { [datetime]$_.Timestamp } -Descending)
    }

    # --- AUTO SNAPSHOT CONFIG ---
    if ($PSCmdlet.ParameterSetName -eq 'Auto') {
        $config = @{ AutoSnapshot = $AutoSnapshot; Updated = (Get-Date).ToString('o') }
        $config | ConvertTo-Json | Set-Content -Path $autoConfigPath -Encoding UTF8
        if ($AutoSnapshot) {
            Write-Host "  Auto-snapshot enabled. State is captured before every WingetBatch install/update/uninstall." -ForegroundColor Green
            Write-Host "  Undo the last operation with: Restore-WingetSnapshot -UndoLast 1" -ForegroundColor DarkGray
        } else {
            Write-Host "  Auto-snapshot disabled." -ForegroundColor Yellow
        }
        return
    }

    # --- LIST ---
    if ($List) {
        $snapshots = Get-AllSnapshots
        if ($snapshots.Count -eq 0) {
            Write-Host "`n  No snapshots found. Take one with: Restore-WingetSnapshot -Take`n" -ForegroundColor Yellow
            return
        }

        Write-Host ""
        Write-Host "  Package State Snapshots" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  $("#".PadLeft(3))  $("ID".PadRight(28)) $("Date".PadRight(20)) $("Pkgs".PadLeft(5))  Label" -ForegroundColor DarkGray
        Write-Host "  $('─' * 76)" -ForegroundColor DarkGray

        $i = 0
        foreach ($snap in $snapshots) {
            $i++
            $date = ([datetime]$snap.Timestamp).ToString("yyyy-MM-dd HH:mm:ss")
            Write-Host "  $($i.ToString().PadLeft(3))  " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($snap.Id.PadRight(28)) " -NoNewline -ForegroundColor White
            Write-Host "$($date.PadRight(20)) " -NoNewline -ForegroundColor DarkGray
            Write-Host "$(([string]$snap.PackageCount).PadLeft(5))  " -NoNewline -ForegroundColor Cyan
            Write-Host $snap.Label -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "  $i snapshots | Undo to #N: Restore-WingetSnapshot -UndoLast N" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # --- TAKE ---
    if ($PSCmdlet.ParameterSetName -eq 'Take') {
        $snap = New-WingetSnapshot -Label $(if ($Label) { $Label } else { 'manual' })
        Write-Host ""
        Write-Host "  Snapshot captured: " -NoNewline -ForegroundColor Green
        Write-Host $snap.Id -ForegroundColor Cyan
        Write-Host "    Packages: $($snap.PackageCount) | Label: $($snap.Label)" -ForegroundColor DarkGray
        Write-Host "    Path: $(Join-Path $snapshotDir "$($snap.Id).json")" -ForegroundColor DarkGray
        Write-Host ""
        return [PSCustomObject]$snap
    }

    # --- PRUNE ---
    if ($PSCmdlet.ParameterSetName -eq 'Prune') {
        $cutoff = (Get-Date).AddDays(-$PruneOld)
        $oldSnaps = @(Get-ChildItem -Path $snapshotDir -Filter "snap_*.json" | Where-Object { $_.LastWriteTime -lt $cutoff })
        if ($oldSnaps.Count -eq 0) {
            Write-Host "  No snapshots older than $PruneOld days." -ForegroundColor Green
        } else {
            $oldSnaps | Remove-Item -Force
            Write-Host "  Pruned $($oldSnaps.Count) snapshots older than $PruneOld days." -ForegroundColor Green
        }
        return
    }

    # Current state, used by Diff and rollback
    $currentPkgs = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue)
    $current = @{}
    foreach ($p in $currentPkgs) { if ($p.Id) { $current[$p.Id] = $p } }

    # --- DIFF ---
    if ($Diff) {
        $targetSnap = if ($DiffSnapshotId) { Get-SnapshotFile -Id $DiffSnapshotId } else { Get-AllSnapshots | Select-Object -First 1 }
        if (-not $targetSnap) {
            if ($DiffSnapshotId) { Write-Error "Snapshot '$DiffSnapshotId' not found." }
            else { Write-Host "  No snapshots to diff against." -ForegroundColor Yellow }
            return
        }

        $snapshotIds = @{}
        foreach ($p in $targetSnap.Packages) { $snapshotIds[$p.Id] = $p.Version }

        $added = @($current.Keys | Where-Object { -not $snapshotIds.ContainsKey($_) } | Sort-Object)
        $removed = @($snapshotIds.Keys | Where-Object { -not $current.ContainsKey($_) } | Sort-Object)
        $updated = @($current.Keys | Where-Object { $snapshotIds.ContainsKey($_) -and [string]$current[$_].InstalledVersion -ne [string]$snapshotIds[$_] } | Sort-Object)

        Write-Host ""
        Write-Host "  Diff: $($targetSnap.Id) -> now" -ForegroundColor Cyan
        Write-Host "  Snapshot: $(([datetime]$targetSnap.Timestamp).ToString('yyyy-MM-dd HH:mm')) ($($targetSnap.PackageCount) pkgs, $($targetSnap.Label))" -ForegroundColor DarkGray
        Write-Host "  Current:  $($currentPkgs.Count) packages" -ForegroundColor DarkGray
        Write-Host ""

        foreach ($id in $added | Select-Object -First 20) { Write-Host "    + $id ($($current[$id].InstalledVersion))" -ForegroundColor Green }
        foreach ($id in $removed | Select-Object -First 20) { Write-Host "    - $id (was $($snapshotIds[$id]))" -ForegroundColor Red }
        foreach ($id in $updated | Select-Object -First 20) { Write-Host "    ~ $id : $($snapshotIds[$id]) -> $($current[$id].InstalledVersion)" -ForegroundColor Yellow }
        if (($added.Count + $removed.Count + $updated.Count) -eq 0) {
            Write-Host "  No changes since this snapshot." -ForegroundColor Green
        }
        elseif ([Math]::Max([Math]::Max($added.Count, $removed.Count), $updated.Count) -gt 20) {
            Write-Host "  (first 20 of each shown) Added: $($added.Count) Removed: $($removed.Count) Changed: $($updated.Count)" -ForegroundColor DarkGray
        }
        Write-Host ""
        return [PSCustomObject]@{ SnapshotId = $targetSnap.Id; Added = $added; Removed = $removed; Changed = $updated }
    }

    # --- Resolve rollback target ---
    $targetSnap = $null
    switch ($PSCmdlet.ParameterSetName) {
        'Undo' {
            $snapshots = Get-AllSnapshots
            if ($snapshots.Count -lt $UndoLast) {
                Write-Error "Not enough snapshots to undo $UndoLast operation(s). Available: $($snapshots.Count)"
                return
            }
            $targetSnap = $snapshots[$UndoLast - 1]
        }
        'Since' {
            $targetSnap = Get-AllSnapshots | Where-Object { [datetime]$_.Timestamp -le $Since } | Select-Object -First 1
            if (-not $targetSnap) {
                Write-Error "No snapshot found at or before $($Since.ToString('yyyy-MM-dd HH:mm'))."
                return
            }
        }
        'Restore' {
            $targetSnap = Get-SnapshotFile -Id $SnapshotId
            if (-not $targetSnap) {
                Write-Error "Snapshot '$SnapshotId' not found. Use -List to see available snapshots."
                return
            }
        }
    }

    Write-Host ""
    Write-Host "  Rolling back to: $($targetSnap.Id) ($(([datetime]$targetSnap.Timestamp).ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor Cyan
    Write-Host "  Label: $($targetSnap.Label)" -ForegroundColor DarkGray

    # --- Plan ---
    $snapshotPkgs = @{}
    foreach ($p in $targetSnap.Packages) { $snapshotPkgs[$p.Id] = $p }

    $toInstall = @($snapshotPkgs.Values | Where-Object { -not $current.ContainsKey($_.Id) -and $_.Source } | Sort-Object Id)
    $toUninstall = @($current.Values | Where-Object { -not $snapshotPkgs.ContainsKey($_.Id) -and $_.Source } | Sort-Object Id)
    $skipped = @($current.Values | Where-Object { -not $snapshotPkgs.ContainsKey($_.Id) -and -not $_.Source })
    $toRevert = @()
    if ($RestoreVersions) {
        $toRevert = @($current.Values | Where-Object {
            $_.Source -and $snapshotPkgs.ContainsKey($_.Id) -and $snapshotPkgs[$_.Id].Version -and
            [string]$_.InstalledVersion -ne [string]$snapshotPkgs[$_.Id].Version
        } | Sort-Object Id)
    }

    Write-Host ""
    Write-Host "  Rollback Plan:" -ForegroundColor White
    foreach ($p in $toInstall) { Write-Host "    + reinstall $($p.Id) v$($p.Version)" -ForegroundColor Green }
    foreach ($p in $toUninstall) { Write-Host "    - uninstall $($p.Id) ($($p.InstalledVersion))" -ForegroundColor Red }
    foreach ($p in $toRevert) { Write-Host "    ~ revert    $($p.Id) $($p.InstalledVersion) -> $($snapshotPkgs[$p.Id].Version)" -ForegroundColor Yellow }
    if ($skipped.Count -gt 0) {
        Write-Host "    ($($skipped.Count) newly added program(s) have no WinGet source and will be left alone)" -ForegroundColor DarkGray
    }
    Write-Host ""

    $totalActions = $toInstall.Count + $toUninstall.Count + $toRevert.Count
    if ($totalActions -eq 0) {
        Write-Host "  Already at target state. Nothing to do." -ForegroundColor Green
        if (-not $RestoreVersions) {
            Write-Host "  (Version changes are only rolled back with -RestoreVersions.)" -ForegroundColor DarkGray
        }
        return
    }

    if (-not $Force) {
        $confirm = $PSCmdlet.ShouldContinue("Apply $totalActions change(s) to restore snapshot $($targetSnap.Id)?", "Confirm Rollback")
        if (-not $confirm) {
            Write-Host "  Rollback cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Safety snapshot so the rollback itself can be undone
    New-WingetSnapshot -Label "pre-rollback-safety" | Out-Null

    $successCount = 0
    $failCount = 0
    $run = {
        param($label, $result)
        Write-Host "  $label" -NoNewline
        if ($result.Succeeded) { Write-Host " [OK]" -ForegroundColor Green; return $true }
        Write-Host " [FAIL] $($result.Message)" -ForegroundColor Red
        return $false
    }

    foreach ($p in $toInstall) {
        $r = Invoke-WingetPackageAction -Action Install -Id $p.Id -Version $p.Version -Source $p.Source -Options @{ Mode = 'Silent' }
        if (& $run "+ Installing $($p.Id) v$($p.Version)..." $r) { $successCount++ } else { $failCount++ }
    }
    foreach ($p in $toUninstall) {
        $r = Invoke-WingetPackageAction -Action Uninstall -Id $p.Id -Source $p.Source -Options @{ Mode = 'Silent' }
        if (& $run "- Uninstalling $($p.Id)..." $r) { $successCount++ } else { $failCount++ }
    }
    foreach ($p in $toRevert) {
        $ver = $snapshotPkgs[$p.Id].Version
        $r = Set-WingetPackageVersion -Id $p.Id -Version $ver -Source $p.Source
        if (& $run "~ Reverting $($p.Id) to $ver..." $r) { $successCount++ } else { $failCount++ }
    }

    Write-Host ""
    Write-Host "  Rollback complete: $successCount succeeded, $failCount failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host "  (Safety snapshot saved: undo this rollback with Restore-WingetSnapshot -UndoLast 1)" -ForegroundColor DarkGray
    Write-Host ""
}
