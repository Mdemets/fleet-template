# Fleet setup: reproducing the current arrangement

The working state as of 2026-11-27, and the steps that build it. Everything here is measured;
measurements and the failures that produced them are in `parallel-workers-2026-11-27.md` and
`lessons-2026-11-27.md`.

## Topology

| Station | Role | Address | Share access | Slots |
|---|---|---|---|---|
| node-a | coordinator | `10.0.0.10` static (Wi-Fi) | local `D:\fleet` | 16 |
| node-b | worker | `10.0.0.11` static | `\\10.0.0.10\fleet` | 8 |
| node-c | worker | DHCP | `\\10.0.0.10\fleet` | 8 |

Measured throughput of that arrangement: **200 tasks in 6.4 s (31.4 tasks/s), zero duplicates**.

## Coordinator

    setup-transport.ps1 -Role coordinator -SharePath D:\fleet -Accounts 'fleet-worker-b','fleet-worker-c'

Creates the share and `queue/ claimed/ results/ locks/ findings/`, creates the share, grants the
worker accounts **Modify on `locks/`**, writes `coordinator.unc` pointing at the local path, and
registers `FleetReaper` every 5 minutes.

Two things are load-bearing:

- **`locks/` must be writable by the worker accounts.** Claim markers go there because `queue/` refuses
  creates for those accounts. A marker that cannot be created makes the worker skip every task
  **silently** - no error, no heartbeat change, just an idle station.
- **The coordinator works from the local path.** SMB loopback to a share on the same machine is
  refused, so a UNC path would leave the coordinator unable to see its own queue.

## Worker

    setup-transport.ps1 -Role worker -CoordinatorUnc \\10.0.0.10\fleet -Node node-b -Slots 8

Writes `node.txt` and `coordinator.unc`, deploys `FleetAgent.ps1`, and registers `FleetAgent` to run
at startup as SYSTEM. The credential pair (`coordinator.user`, `coordinator.cred` - DPAPI
LocalMachine, so only decryptable on that machine) is provisioned separately and is the one thing this
script will not create for you.

## Why the agent and not N workers

One process per station owns the share session; parallelism is a runspace pool inside it. A child
process does **not** inherit its parent's network session - three designs failed that way (UNC slots,
drive-letter slots under a dedicated account, pooled slots under SYSTEM), each hanging before its
first heartbeat. Runspaces share the agent's process and therefore its session.

## Per-station prerequisites

1. **Static address** on the coordinator, and preferably every station. A DHCP lease change silently
   breaks every worker's `coordinator.unc`.
2. **sshd** for administration, key-based, and `administrators_authorized_keys` for the operator key.
3. **Worker identity** on the coordinator: one local account per station, Change on the share, Modify
   on `locks/`.
4. **Same password on the same account name across coordinators**, so a failover needs no rotation.
   Misalignment fails auth with System error 86 and, through retries, locks the account.
5. **WMI healthy**: `Get-NetIPAddress` and `Get-NetTCPConnection` must answer. If they fail with
   `Invalid class`, recompile the provider: `mofcomp %windir%\System32\wbem\NetTCPIP.mof`. A reboot
   does not fix it; the repository is consistent, only the class registrations are missing.

## Verification

| Check | Command | Pass |
|---|---|---|
| agent alive | `Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"` | one `FleetAgent` per station |
| heartbeats | `<share>\results\<node>\heartbeat.json` | age < 30 s, carries `active` |
| reaper | `<share>\reaper.log` | a sweep every ~300 s, `dead=0` |
| throughput | `scripts/audit-efficiency.ps1` | see the measured table above |
| distribution | run a burst, group results by node | every station contributes |

**Always check per-node distribution, not just "drained N/N".** During this work the coordinator
covered for broken workers three times; a burst that only reports completion hid every failure.

## Failover

`scripts/fleet-failover.ps1 -To <node>` repoints the workers, enables or disables the standby reaper,
and verifies heartbeats. Its assumption is the shared account password; break that and the switch
fails auth. Drain the queue first - two live primaries must never coexist.
## Auditor

The auditor is a role, not a leftover. It needs read-only access to the share, reachability to every
station, and - the point of the role - **a host that is not the node it audits**. Running it as a
worker slot defeats it: the machine is then loaded by the work it is measuring.

    scripts/assess-fleet.ps1 -Hosts <all stations> -AuditorHost <the auditor host>

The assessment recommends an auditor when none is given (least-loaded non-coordinator), and states
plainly when no independent host exists. Give it a read-only share account: the auditor reads
`results/`, `claimed/` and `reaper.log`; it never claims tasks.

Day-to-day it runs `audit-fleet.ps1`, `audit-station.ps1`, `audit-coordinator.ps1` and
`audit-efficiency.ps1`, and records findings where the fleet will read them (`docs/` for method,
`findings/` on the share for project-specific work).