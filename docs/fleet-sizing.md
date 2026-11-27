# Fleet sizing: roles, capacity, and how to decide

The template must fit hardware it has not seen. This is the decision procedure, and the measurements it
is based on. Nothing here assumes three stations, a specific CPU, or a particular subnet.

## Measure first

    scripts/assess-fleet.ps1 -Local -Hosts <worker1>,<worker2>

It probes each station (cores, threads, RAM, share disk, address, static-ness) and self-measures
scaling by running a fixed workload at 1 and at thread-count concurrency. Output is a table plus a
recommendation.

## Assigning roles

| Role | Requirements | Decision rule |
|---|---|---|
| **coordinator** | the share lives here; every worker depends on it | static address first, then most share disk, then RAM. Stability beats speed. |
| **worker** | reaches the share; runs payloads | everything else, including the coordinator from its local path |
| **auditor** | read-only share access; reachability to every station | a host that is **not** the coordinator and preferably outside the fleet; it must not audit the machine it runs on |
| **standby** | same account password as the coordinator | optional; a second host that can take the share |

The coordinator is a reliability choice, not a performance one. The busiest machine makes a poor
coordinator if its address is dynamic or it reboots often.

## Slots per station

Measured on the 2026-11-27 fleet (iterations in 4 s, summed across concurrent slots):

| Station | 1 slot | 4 | 8 | 16 | 32 |
|---|---|---|---|---|---|
| 24 cores / 32 threads | 1.0x | 3.95x | 6.65x | 10.27x | **19.72x** |
| 8 cores / 16 threads | 1.0x | 3.40x | 6.49x | **10.84x** | 13.76x |

Interpreter-bound payloads (PowerShell scripts, a forked build, a test sweep) keep gaining past the
thread count because they wait. **Compiled payloads saturate at cores.**

Rule of thumb from that data:

- **interpreter-bound:** slots = logical threads, floored at 4, capped at 32;
- **compiled/CPU-bound:** slots = physical cores, floored at 2;
- if in doubt, start at threads and measure the per-slot efficiency after a burst.

At 65-80 % per-slot efficiency you are near the useful point; below 50 % the extra slots are buying
throughput at real contention cost.

## How parallelism is delivered

One agent process per station with a runspace pool. A child process does **not** inherit its parent's
network session (three designs failed that way), and runspaces live inside the agent's process. So the
unit of scaling is slots *inside* the agent, not processes.

## Layers

| Layer | What it is | Scales by |
|---|---|---|
| share | `queue/`, `claimed/`, `results/`, `locks/` | disk and reliability, not CPU |
| agent | one process per station, runspace pool | slots per station |
| reaper | claim ageing, dead tasks, pruning | stays one; it is a janitor |
| auditor | read-only measurement and reporting | one per fleet; runs outside the worker pool |

Do not run the auditor as a worker slot. Its value is independence, and a worker is loaded by the very
work it is measuring.

## Re-measure after deploy

1. Run a burst sized to the slot total (e.g. 200 tasks at 500 ms).
2. Read **per-node distribution**, not the drained count - the coordinator covering for a broken
   worker is the failure mode that hides itself.
3. `scripts/audit-efficiency.ps1` for utilisation and execution-time spread.
4. `scripts/audit-fleet.ps1` for transport health: claims that produced results, dead letters, retries.

If a station contributes nothing while its agent runs, check in this order: can the worker account
**create a file** in `locks/`; is `coordinator.unc` correct (two backslashes); does the agent log show a
session established. Each of those has silently idled a station before.