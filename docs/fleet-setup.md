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

Measured throughput of that arrangement, 2026-11-27, three stations at 16/32/16 slots:

| measurement | value |
|---|---|
| creation rate (coordinator) | ~40 dispatches/s sustained |
| completion rate (fleet) | ~26 dispatches/s |
| per station | mdma 8.2/s, gr2c3p8 7.1/s, mdmfury 0.7/s (parked by policy) |
| peak concurrency | 16/16, 25/32, 16/16 = 87.5% of 64 slots |
| queue at steady state | several hundred, refill-triggered |

The earlier figure - 200 tasks in 6.4 s, 31.4 tasks/s - was a synthetic burst against an empty queue
and measured claim/drain speed, not sustained throughput. Both are real; they answer different
questions. Monitoring figures and their failure modes: docs/monitoring.md. Supply side:
docs/task-creation.md.

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

## Measurement traps

Added 2026-11-27. Every row is a wrong conclusion that was acted on before it was caught, and the
check that now catches it. A fleet that measures itself badly looks healthy while doing nothing.

| Trap | What happened | Check |
|---|---|---|
| One page is not the population | A single `per_page=30` query reported 29 open issues. The repository held 450, and 577 upstream. Fleet capacity was then reasoned from the wrong number. | Count with `gh api --paginate`, and corroborate against `repos/<owner>/<repo>.open_issues_count`. |
| Two clocks | The dashboard computed "finished in the last 15 min" as UTC-now against local file times. Local was UTC+1, so the window was 75 minutes: 117 reported, 0 real. | Subtract in one clock. This is the same root cause as the existing rule that claim age drives the reaper. |
| Stale counters | `runningCount` counted claim files, archived ones included, and read 2 while `active` was 0. `active` itself lags heartbeats by seconds. | Name the field that means "working now", and derive it from claim age rather than file presence. |
| Same path, different repository | `...\projects\victory` was `JMAN730/victory` at `820bc3b` on one station, `marvisak/victory` at `da82e44` on another, upstream `63bcca4`. | Every station reports `remote get-url origin` and `rev-parse HEAD`. A result carrying neither is not comparable. |
| Existence is not ancestry | `git cat-file -e <sha>` succeeds for a commit merely present in the object store. Seventeen fixes were reported absent from a tree that could not have contained them, then reported present once the base commit advanced. | `cat-file -t` must be `commit`, then `merge-base --is-ancestor`. State the base commit beside the answer. |
| Hash-shaped is not a commit | A regex over issue bodies matched a title binary's blake3 digest as a commit id. | Validate the object type before treating any hex token as a commit. |
| Depth-limited search | `Get-ChildItem -Depth 4` reported `victory.exe` absent; it existed at depth 6 under `target\`. | Never conclude absence from a depth-limited or filtered search. |
| Wrong machine | `gh auth login` reported the device connected, but the token was stored on the operator's workstation. The coordinator stayed at HTTP 401 through several retries. | Verify identity where it must be used: `gh api user --jq .login` on that host. |
| Two credential paths | Authenticating `gh` did not fix `git push`: gh uses its own store, push used Git Credential Manager and failed with `could not read Username`. | After authenticating, run `gh auth setup-git` and prove it with `git push --dry-run`. |
| Credential reachable by the fleet | The token file was readable by the account tasks run under (`NT AUTHORITY\SYSTEM FullControl`), so any queued task could act as the auditor. | The coordinator holds no credential. Reading public issue lists needs none. Outward actions run from the auditor's machine. |
| Session-bound builds | A release build started in an SSH foreground died with the session and left no binary, while still appearing to have started. | Start long work detached (`Win32_Process.Create` or a scheduled task) and poll a log file. |
| Account prerequisites | Running as the machine account, git refused with `dubious ownership` and cargo with `no default toolchain`. | Provision `safe.directory` for the repositories and `RUSTUP_HOME`/`CARGO_HOME` for that account, then prove both. |

The general form: a number needs its clock, its commit, its population and its base. Any of the four
missing produces a confident answer that is wrong, and nothing in the fleet raises an error.

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