# Fleet minimum requirements

What a station needs before it can join, and what disqualifies it. Derived from the constraints that
actually bit the 2026-11-27 fleet, not from a specification.

## The transport in one line

One coordinator hosts an SMB share; each station runs an agent that **pulls** tasks from that share and
writes results back. There is no inbound connection to a worker and no internet requirement.

## Hard requirements (a station that fails any of these cannot join)

| # | Requirement | Why, and how it was learned |
|---|---|---|
| 1 | **Can reach the coordinator's SMB share (TCP 445)** | The queue is a file share. A station that cannot mount it claims nothing - and does so silently. |
| 2 | **Windows 10/11 or Server 2016+, PowerShell 5.1+** | The agent is a PowerShell runspace host; no dependencies beyond the OS. |
| 3 | **Administrator rights at provisioning time** | Creating the local worker account, the share ACL grant on `locks/`, and the startup task all need elevation. |
| 4 | **A stable coordinator address** | Static IP, DHCP reservation, or DNS name. A lease change breaks every worker's `coordinator.unc` and the fleet goes quiet. |
| 5 | **Clock within a few minutes of the fleet** | Claim age drives the reaper. A skewed clock makes a live claim look stale (requeue, duplicate work) or a dead one look fresh. |
| 6 | **Can run a scheduled task as SYSTEM** | The agent runs at startup as SYSTEM so it survives logoff; a locked-down host that forbids this needs a different supervision model. |

## Not required

| Assumption people make | Reality |
|---|---|
| Same subnet | Not required. Any routed path to the coordinator's 445 works. Subnet only matters for discovery convenience. |
| Admin access at run time | Not required. Provision once as admin; afterwards the agent runs as SYSTEM and the worker account only needs Change on the share and Modify on `locks/`. |
| Internet access | Not required. Nothing calls out. |
| Inbound access to workers | Not required. The pull model means workers dial out; nothing listens except SSH for administration. |
| Identical hardware | Not required, and not desirable - roles follow measurements (`assess-fleet.ps1`). |
| A GPU | Not required. Nothing in the transport touches one. |

## Station roles and their extra needs

| Role | Minimum | Notes |
|---|---|---|
| **worker** | 2 cores, 4 GB RAM, SMB client | 2-4 slots at that size. Interpreter-bound payloads are the normal case. |
| **worker (heavier)** | 8 cores, 16 GB RAM | 8-16 slots; measured 12x scaling at thread count. |
| **coordinator** | any worker spec **plus** storage for the share and the best uptime on the fleet | The share lives here; every worker depends on it. Stability beats speed. |
| **auditor** | read-only share access, SSH reachability, and **not** a node it audits | Independence is the requirement; capacity is not. |

Sizing formula and measured curves: `fleet-sizing.md`.

## Minimum network footprint

| Port | Direction | Purpose | Required |
|---|---|---|---|
| 445/tcp | worker -> coordinator | the queue: claim, result, heartbeat | yes |
| 22/tcp | operator -> any station | administration, provisioning, audits | strongly recommended |
| 5985/5986 | - | WinRM | not used by this design |

Latency matters more than bandwidth: the agent polls when idle, so a high-latency link spends its time
in round trips rather than in work.

## What disqualifies a station

- **Cannot reach 445** - for example a host behind a NAT on the far side of a VPN client connection.
  Verified failure mode: a workstation on the client side of a VPN could reach the LAN, but the LAN
  could not reach it, so it could never serve or be polled.
- **No administrator access ever** - it can run nothing that must start at boot or write to `locks/`.
- **Clock drift beyond minutes** - it corrupts claim ageing.
- **Unreliable power or link as coordinator** - a coordinator that disappears takes the queue with it;
  workers then idle without obvious cause.

## Validate a candidate before adding it

    scripts/check-prerequisites.ps1 -Coordinator 10.0.0.10 -Share \\\\10.0.0.10\\fleet

It reports each requirement as PASS or FAIL with the measured value, so a station is admitted on
evidence rather than on assumption. Exit code is non-zero if any hard requirement fails.

## Growth

Adding a station is: provision the worker account and the `locks/` grant on the coordinator, run
`setup-transport.ps1 -Role worker`, verify with the check above, then run a burst and confirm the new
station appears in the **per-node distribution**. A station that is alive but absent from that
distribution is the failure shape this fleet has hit three times.