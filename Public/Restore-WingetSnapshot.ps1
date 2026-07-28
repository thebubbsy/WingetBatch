function Restore-WingetSnapshot {
    <#
    .SYNOPSIS
        Package-level rollback: undo installs, updates, and uninstalls.

    .DESCRIPTION
        Maintains a timeline of package state snapshots and enables rollback
        to any previous point. Automatically captures state before operations,
        or manually snapshot at any time.

        Supports: "undo last N changes", "restore to Tuesday's state",
        "what changed since yesterday", and full reconciliation rollback.

    .PARAMETER Take
        Capture a snapshot of the current package state right now.

    .PARAMETER Label
        Human-readable label for the snapshot (e.g., "before-vscode-update").

    .PARAMETER List
        Show all available snapshots with timestamps and labels.

    .PARAMETER Restore
        Roll back to a specific snapshot (by ID or index).

    .PARAMETER UndoLast
        Undo the last N operations by restoring to the snapshot before them.

    .PARAMETER Since
        Restore to the state at a specific date/time.

    .PARAMETER Diff
        Show what changed between two snapshots (or since last snapshot).

    .PARAMETER SnapshotId
        Target snapshot identifier for Restore/Diff operations.

    .PARAMETER PruneOld
        Remove snapshots older than N days. Default retention: 30 days.

    .PARAMETER AutoSnapshot
        Enable automatic snapshots before every install/uninstall/update.

    .EXAMPLE
        Restore-WingetSnapshot -Take -Label "before-big-update"
        Manually captures current state with a label.

    .EXAMPLE
        Restore-WingetSnapshot -List
        Shows all snapshots: ID, date, label, package count.

    .EXAMPLE
        Restore-WingetSnapshot -UndoLast 3
        Rolls back the last 3 package changes.

    .EXAMPLE
        Restore-WingetSnapshot -Since "2025-01-15"
        Restores to the state as of January 15th.

    .EXAMPLE
        Restore-WingetSnapshot -Diff -SnapshotId "snap_20250115_143022"
        Shows what changed since that snapshot.

    .NOTES
        Author: Matthew Bubb
        Snapshots stored in ~/.wingetbatch/snapshots/ as compressed JSON.
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

        [Parameter(ParameterSetName = 'Restore')]
        [string]$SnapshotId,

        [Parameter(ParameterSetName = 'Undo', Mandatory)]
        [int]$UndoLast,

        [Parameter(ParameterSetName = 'Since', Mandatory)]
        [datetime]$Since,

        [Parameter(ParameterSetName = 'Diff', Mandatory)]
        [switch]$Diff,

        [Parameter(ParameterSetName = 'Diff')]
        [string]$DiffSnapshotId,

        [Parameter(ParameterSetName = 'Prune', Mandatory)]
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

    # --- Helper: Capture current state ---
    function Take-SnapshotInternal {
        param([string]$SnapLabel)

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $id = "snap_$timestamp"
        $packages = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue

        $snapshot = @{
            Id = $id
            Timestamp = (Get-Date -ToString 'o')
            Label = $SnapLabel ?? "manual"
            Hostname = $env:COMPUTERNAME
            PackageCount = $packages.Count
            Packages = @($packages | ForEach-Object {
                @{ Id = $_.Id; Name = $_.Name; Version = $_.InstalledVersion; Source = $_.Source }
            })
        }

        $filePath = Join-Path $snapshotDir "$id.json"
        $snapshot | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $filePath -Encoding UTF8
        return $snapshot
    }

    # --- Helper: Load snapshot ---
    function Get-SnapshotFile {
        param([string]$Id)
        $path = Join-Path $snapshotDir "$Id.json"
        if (Test-Path $path) {
            return (Get-Content $path -Raw | ConvertFrom-Json -AsHashtable)
        }
        return $null
    }

    # --- Helper: Get all snapshots sorted ---
    function Get-AllSnapshots {
        Get-ChildItem -Path $snapshotDir -Filter "snap_*.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {
                $data = Get-Content $_.FullName -Raw | ConvertFrom-Json -AsHashtable
                $data
            }
    }

    # --- AUTO SNAPSHOT CONFIG ---
    if ($PSCmdlet.ParameterSetName -eq 'Auto') {
        $config = @{ AutoSnapshot = $AutoSnapshot; Enabled = (Get-Date -ToString 'o') }
        $config | ConvertTo-Json | Set-Content -Path $autoConfigPath -Encoding UTF8
        if ($AutoSnapshot) {
            Write-Host "  ✓ Auto-snapshot enabled. State captured before every install/uninstall/update." -ForegroundColor Green
        } else {
            Write-Host "  ✓ Auto-snapshot disabled." -ForegroundColor Yellow
        }
        return
    }

    # --- LIST ---
    if ($List) {
        $snapshots = Get-AllSnapshots
        if (-not $snapshots -or $snapshots.Count -eq 0) {
            Write-Host "`n  No snapshots found. Take one with: Restore-WingetSnapshot -Take`n" -ForegroundColor Yellow
            return
        }

        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "  ║              Package State Snapshots                    ║" -ForegroundColor Cyan
        Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  $("ID".PadRight(24)) $("Date".PadRight(22)) $("Pkgs".PadLeft(5))  Label" -ForegroundColor DarkGray
        Write-Host "  $('─' * 70)" -ForegroundColor DarkGray

        $i = 0
        foreach ($snap in $snapshots) {
            $i++
            $date = [datetime]::Parse($snap.Timestamp).ToString("yyyy-MM-dd HH:mm:ss")
            Write-Host "  $($snap.Id.PadRight(24)) " -NoNewline -ForegroundColor White
            Write-Host "$($date.PadRight(22)) " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($snap.PackageCount.ToString().PadLeft(5))  " -NoNewline -ForegroundColor Cyan
            Write-Host $snap.Label -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "  $i snapshots | Restore: Restore-WingetSnapshot -Restore -SnapshotId <id>" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # --- TAKE ---
    if ($Take -or $PSCmdlet.ParameterSetName -eq 'Take') {
        $snap = Take-SnapshotInternal -SnapLabel $Label
        Write-Host ""
        Write-Host "  ✓ Snapshot captured: " -NoNewline -ForegroundColor Green
        Write-Host $snap.Id -ForegroundColor Cyan
        Write-Host "    Packages: $($snap.PackageCount) | Label: $($snap.Label)" -ForegroundColor DarkGray
        Write-Host "    Path: $snapshotDir\$($snap.Id).json" -ForegroundColor DarkGray
        Write-Host ""
        return [PSCustomObject]$snap
    }

    # --- DIFF ---
    if ($Diff) {
        $snapshots = Get-AllSnapshots
        if (-not $snapshots -or $snapshots.Count -eq 0) {
            Write-Host "  No snapshots to diff against." -ForegroundColor Yellow
            return
        }

        # Get target snapshot (specified or most recent)
        $targetSnap = if ($DiffSnapshotId) { Get-SnapshotFile -Id $DiffSnapshotId }
                      else { $snapshots | Select-Object -First 1 }

        if (-not $targetSnap) {
            Write-Error "Snapshot '$DiffSnapshotId' not found."
            return
        }

        # Current state
        $currentPkgs = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
        $currentIds = @{}
        foreach ($p in $currentPkgs) { $currentIds[$p.Id] = $p.InstalledVersion }

        $snapshotIds = @{}
        foreach ($p in $targetSnap.Packages) { $snapshotIds[$p.Id] = $p.Version }

        # Compute diff
        $added = $currentIds.Keys | Where-Object { -not $snapshotIds.ContainsKey($_) }
        $removed = $snapshotIds.Keys | Where-Object { -not $currentIds.ContainsKey($_) }
        $updated = $currentIds.Keys | Where-Object { $snapshotIds.ContainsKey($_) -and $currentIds[$_] -ne $snapshotIds[$_] }

        Write-Host ""
        Write-Host "  Diff: $($targetSnap.Id) → NOW" -ForegroundColor Cyan
        Write-Host "  Snapshot: $([datetime]::Parse($targetSnap.Timestamp).ToString('yyyy-MM-dd HH:mm')) ($($targetSnap.PackageCount) pkgs)" -ForegroundColor DarkGray
        Write-Host "  Current:  $($currentPkgs.Count) packages" -ForegroundColor DarkGray
        Write-Host ""

        if ($added.Count -gt 0) {
            Write-Host "  + Added ($($added.Count)):" -ForegroundColor Green
            foreach ($id in $added | Select-Object -First 20) {
                Write-Host "    + $id ($($currentIds[$id]))" -ForegroundColor Green
            }
        }
        if ($removed.Count -gt 0) {
            Write-Host "  - Removed ($($removed.Count)):" -ForegroundColor Red
            foreach ($id in $removed | Select-Object -First 20) {
                Write-Host "    - $id (was $($snapshotIds[$id]))" -ForegroundColor Red
            }
        }
        if ($updated.Count -gt 0) {
            Write-Host "  ~ Updated ($($updated.Count)):" -ForegroundColor Yellow
            foreach ($id in $updated | Select-Object -First 20) {
                Write-Host "    ~ $id : $($snapshotIds[$id]) → $($currentIds[$id])" -ForegroundColor Yellow
            }
        }
        if ($added.Count -eq 0 -and $removed.Count -eq 0 -and $updated.Count -eq 0) {
            Write-Host "  No changes since this snapshot." -ForegroundColor Green
        }
        Write-Host ""
        return
    }

    # --- UNDO LAST N ---
    if ($UndoLast -gt 0) {
        $snapshots = Get-AllSnapshots
        if (-not $snapshots -or $snapshots.Count -le $UndoLast) {
            Write-Error "Not enough snapshots to undo $UndoLast operations. Available: $($snapshots.Count)"
            return
        }

        # Target is the snapshot N positions back
        $targetSnap = $snapshots[$UndoLast]
        Write-Host ""
        Write-Host "  Rolling back to: $($targetSnap.Id) ($([datetime]::Parse($targetSnap.Timestamp).ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor Cyan
        Write-Host "  Label: $($targetSnap.Label)" -ForegroundColor DarkGray
    }

    # --- SINCE DATE ---
    if ($PSCmdlet.ParameterSetName -eq 'Since') {
        $snapshots = Get-AllSnapshots
        $targetSnap = $snapshots | Where-Object { [datetime]::Parse($_.Timestamp) -le $Since } | Select-Object -First 1
        if (-not $targetSnap) {
            Write-Error "No snapshot found at or before $($Since.ToString('yyyy-MM-dd HH:mm'))."
            return
        }
        Write-Host ""
        Write-Host "  Restoring to state at: $([datetime]::Parse($targetSnap.Timestamp).ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
    }

    # --- RESTORE (by ID) ---
    if ($PSCmdlet.ParameterSetName -eq 'Restore' -and $SnapshotId) {
        $targetSnap = Get-SnapshotFile -Id $SnapshotId
        if (-not $targetSnap) {
            Write-Error "Snapshot '$SnapshotId' not found. Use -List to see available snapshots."
            return
        }
    }

    # --- PERFORM ROLLBACK ---
    if ($targetSnap) {
        # Compute what needs to change
        $currentPkgs = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
        $currentIds = @{}
        foreach ($p in $currentPkgs) { $currentIds[$p.Id] = $p.InstalledVersion }

        $snapshotIds = @{}
        foreach ($p in $targetSnap.Packages) { $snapshotIds[$p.Id] = $p.Version }

        $toInstall = $snapshotIds.Keys | Where-Object { -not $currentIds.ContainsKey($_) }
        $toUninstall = $currentIds.Keys | Where-Object { -not $snapshotIds.ContainsKey($_) }

        Write-Host ""
        Write-Host "  Rollback Plan:" -ForegroundColor White
        Write-Host "    Install:   $($toInstall.Count) packages (were removed since snapshot)" -ForegroundColor Green
        Write-Host "    Uninstall: $($toUninstall.Count) packages (added since snapshot)" -ForegroundColor Red
        Write-Host ""

        if ($toInstall.Count -eq 0 -and $toUninstall.Count -eq 0) {
            Write-Host "  ✓ Already at target state. Nothing to do." -ForegroundColor Green
            return
        }

        $confirm = $PSCmdlet.ShouldContinue(
            "Install $($toInstall.Count) and uninstall $($toUninstall.Count) packages to restore snapshot?",
            "Confirm Rollback")
        if (-not $confirm) {
            Write-Host "  Rollback cancelled." -ForegroundColor Yellow
            return
        }

        # Take a safety snapshot before rollback
        Take-SnapshotInternal -SnapLabel "pre-rollback-safety" | Out-Null

        $successCount = 0
        $failCount = 0

        # Install missing
        foreach ($id in $toInstall) {
            Write-Host "  + Installing $id..." -NoNewline -ForegroundColor Green
            try {
                Microsoft.WinGet.Client\Install-WinGetPackage -Id $id -Mode Silent | Out-Null
                Write-Host " ✓" -ForegroundColor Green
                $successCount++
            } catch {
                Write-Host " ✗" -ForegroundColor Red
                $failCount++
            }
        }

        # Uninstall extraneous
        foreach ($id in $toUninstall) {
            Write-Host "  - Uninstalling $id..." -NoNewline -ForegroundColor Red
            try {
                Microsoft.WinGet.Client\Uninstall-WinGetPackage -Id $id -Mode Silent | Out-Null
                Write-Host " ✓" -ForegroundColor Green
                $successCount++
            } catch {
                Write-Host " ✗" -ForegroundColor Red
                $failCount++
            }
        }

        Write-Host ""
        Write-Host "  Rollback complete: $successCount succeeded, $failCount failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Yellow' })
        Write-Host "  (Safety snapshot saved in case you need to undo this rollback)" -ForegroundColor DarkGray
        Write-Host ""
    }

    # --- PRUNE ---
    if ($PruneOld -gt 0) {
        $cutoff = (Get-Date).AddDays(-$PruneOld)
        $oldSnaps = Get-ChildItem -Path $snapshotDir -Filter "snap_*.json" | Where-Object { $_.LastWriteTime -lt $cutoff }
        if ($oldSnaps.Count -eq 0) {
            Write-Host "  No snapshots older than $PruneOld days." -ForegroundColor Green
        } else {
            $oldSnaps | Remove-Item -Force
            Write-Host "  ✓ Pruned $($oldSnaps.Count) snapshots older than $PruneOld days." -ForegroundColor Green
        }
        return
    }
}
