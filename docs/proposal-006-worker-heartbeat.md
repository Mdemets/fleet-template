# 006 - Heartbeat, so a dead worker is visible from the coordinator

Status: accepted and applied 2026-11-27 10:20Z.`n`nVerified: results/node-b/heartbeat.json and results/node-c/heartbeat.json, ages 8s and 32s during the test.

## Why

The worker is an endless loop, so the scheduled task reports Running whether it is healthy or
locked out. During the 2026-11-27 outage the coordinator saw a healthy fleet while half of it was
dead. Nothing contradicted that view.

## Patch - worker writes a heartbeat every sweep (results/<node>/heartbeat.json)

    @{ ts=(Get-Date).ToUniversalTime().ToString('o'); node=$node; queue=$files.Count } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $myRes 'heartbeat.json') -Encoding ascii

Written before the sleep, so at most one poll interval of staleness (10-20s).

## Patch - audit reports node age

In audit-station.ps1 / audit-fleet.ps1: read results/<node>/heartbeat.json and report its age. Older
than 5 minutes marks the node STALE; absent marks it UNKNOWN (never 'idle').

## Why the wording matters

The first audit of the day reported a stalled fleet because the queue was empty. Absence of evidence
must be reported as unknown, not as health.

## Risk

Very low: one small file per node per sweep.

## Revert

Remove the write and the reader.

