# 004 - Reaper must measure the claim's age, not the task's

Status: accepted and applied 2026-11-27 10:21Z.`n`nApplied as the claims sidecar (results/<node>/claims/<id>.json): the worker cannot modify a claim after moving it - write-data is denied on claimed/ - so the claim time is recorded where results are written. Verified: a task backdated 2h was claimed and NOT requeued while running.

## Why

Move-Item within the share preserves LastWriteTime. Measured: a file backdated 3 hours kept its
timestamp after the move, so the reaper saw 10800s of age on a claim made seconds earlier. Any task
that waited longer than timeoutSeconds+300 is requeued the instant it is claimed, while the worker
is still running it.

## Patch A - worker stamps the claim (FleetWorker.ps1, after the move succeeds)

    $dest = Join-Path $myClaim $f.Name
    try { Move-Item -LiteralPath $f.FullName -Destination $dest -ErrorAction Stop } catch { continue }
    (Get-Item -LiteralPath $dest).LastWriteTime = Get-Date      # claim time, not task time

## Patch B - reaper prefers an explicit claim time (Invoke-FleetReaper.ps1, replaces line 55)

    $claimedAt = $f.LastWriteTime.ToUniversalTime()
    if ($task.PSObject.Properties['claimedAt'] -and $task.claimedAt) {
        try { $claimedAt = [datetime]::Parse([string]$task.claimedAt).ToUniversalTime() } catch { }
    }
    $age = [int](($now - $claimedAt).TotalSeconds)

Patch A alone fixes it for this fleet. B makes it survive a filesystem that behaves differently.

## Risk

Low. If a worker does not stamp, the reaper keeps the current behaviour for that claim.

## Revert

Two lines; revert means removing the stamp and restoring the single age expression.

