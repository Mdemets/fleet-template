# Coordinator: primary and standby

Set up 2026-11-27 because node-a was down and node-b took over. The operator chose to keep node-b
as a standby rather than retire it.

| | node-a | node-b |
|---|---|---|
| Role in normal operation | **primary** | **standby** |
| Share | `\\10.0.0.10\fleet` (D:/fleet) | `\\10.0.0.11\fleet` (C:/fleetshare) |
| Reaper | enabled | **disabled** while on standby |
| FleetWorker | enabled | enabled (worker) |
| Role during failover | down | **primary**; its worker is disabled because of the SMB loopback check |

## The one thing that makes failover cheap

`fleet-worker-c` must carry the **same password on both hosts**. The worker's stored credential then
works against either, and a failover is just a UNC change - no rotation, no lockout risk.

This is the assumption to check first if auth fails after a switch. If the passwords have drifted,
fix the account; do not rekey the worker blindly, which is what caused the 2026-11-27 lockout.

## Switching

    powershell -File scripts/fleet-failover.ps1 -To node-b      # primary down
    powershell -File scripts/fleet-failover.ps1 -To node-a   # primary back

The script drains nothing by itself: it prints the target's queue depth first. Do not switch with
tasks in flight on the target, and do not leave two primaries live - each has its own queue and
results history, and they do not merge.

## Known fragility

Both hosts are on DHCP. A lease change breaks the workers' `coordinator.unc` silently. Reservations
on the router for `.196` and `.118` remove the failure mode entirely.

## Address pinning

**node-b is static as of 2026-11-27**: `10.0.0.11/24`, gateway `10.0.0.1`, DNS
`192.0.2.53` / `192.0.2.54`, DHCP disabled on the adapter. Set on the same address it already
had, so no worker configuration changed. Verified afterwards: host still answers, name resolution
works, and the worker heartbeat kept refreshing through the change.

**node-a is still DHCP** and must be pinned the same way when it returns, or reserved on the
router for `.196`. Until then a lease change on the primary silently breaks `coordinator.unc` on
both workers.