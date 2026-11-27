# FALLBACK COORDINATOR - temporary

This share is the fleet's coordinator only because node-a is unavailable (reboot 2026-11-27, did
not return; see fleet-template docs/incident-2026-11-27-reboot.md).

| | |
|---|---|
| Share | `\\10.0.0.11\fleet` -> `C:\fleetshare` |
| Host | node-b (10.0.0.11, DHCP) |
| Workers | node-c only, authenticating as `fleet-worker-c` |
| node-b's own worker | **disabled** - it is the coordinator now, and a worker cannot authenticate to its own share through the SMB loopback check |
| Reaper | scheduled task `FleetReaper`, SYSTEM, 5 minutes, `-Root C:\fleetshare` |

## What is NOT here

- The queue and results history from node-a. This share started empty; nothing was copied because
  the source was unreachable. No task was in flight at the time, so nothing was lost.
- The integration repository. The flamingo line was restored separately on node-b at
  `C:\\Users\\<user>\flamingo` from the off-site bundle, and it passes 564 tests.

## When node-a returns

Decide which host is authoritative before resuming normal work. Two shares with separate histories
must not both be live: pick one, drain it, and retire the other. Also re-enable node-b's `FleetWorker`
if node-b goes back to being a worker.

## Known fragility

node-b is on DHCP. If its lease changes, DESKTOP's `coordinator.unc` breaks and the transport stops
silently until someone notices. A reservation on the router, or a static address, removes this.