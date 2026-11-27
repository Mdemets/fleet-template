# Fleet parallelism: the local agent design (working)

Final, measured arrangement. Replaces every earlier attempt in this file.

## The design

**One agent process per station. It owns the share session. Parallelism happens inside it.**

A child process does not inherit a network session from its parent - proven three ways: UNC slots
spawned by a supervisor, drive-letter slots under a dedicated account, and pooled slots under SYSTEM.
All three hung silently before their first task. Runspaces live inside the agent's process and use its
session, so they work.

| Station | Slots | Share |
|---|---|---|
| node-a | 16 | local `D:\fleet` |
| node-b | 8 | `\\10.0.0.10\fleet` |
| node-c | 8 | `\\10.0.0.10\fleet` |

## Measured

| Metric | Original (1 worker, 30 s poll) | Agent |
|---|---|---|
| throughput | ~0.03 tasks/s | **33.8 tasks/s** |
| 300 tasks | ~2.8 hours (projected) | **8.9 s** |
| per station | 1 | 16 / 8 / 8 runspaces |
| duplicates | 2 % under load | **0** |
| non-zero exits | - | **0** |

Distribution of a 200-task burst: node-a 140, node-b 31, DESKTOP 29. Heartbeats from all three carry
`active` (runspaces in flight), not just a timestamp.

## Why the earlier attempts failed

Each is a lesson, not just history:

1. **Child processes do not inherit the SMB session.** Slots hung before their first heartbeat.
   Runspaces sidestep it entirely.
2. **`Connect-Fleet` starts with `Remove-SmbMapping -Force`.** With 32 slots, one slot's connect tore
   down another's session. In an agent there is exactly one connection.
3. **The worker account cannot create files in `queue/`.** Claim markers now live in `locks/`, granted
   to the worker identities. Without that grant, a marker create fails and the `continue` skips the
   task **silently** - 32 slots, no tasks, no errors.
4. **A `continue` on a permission failure is a silent worker.** Log it once; that line is the difference
   between five minutes and five hours.

## Files

- `FleetAgent.ps1` in each station's fleet directory (agent + runspace pool).
- Scheduled task `FleetAgent`, SYSTEM, at startup:
  `powershell -File <dir>\FleetAgent.ps1 -Slots N`
- Claim markers: `<share>\locks\<task>.claim`, created exclusively; the winner moves the task.
- Results and `claims/<id>.json` sidecar per node, as before.

## Remaining limits

- Slots are PowerShell runspaces: they share one core pool per process and one .NET heap. For CPU-bound
  payloads this behaves like 16 threads, not 16 processes.
- A payload that crashes the agent takes that station's slots with it; the task is requeued by the
  reaper after the claim ages out.
- Claim markers are removed on completion; a marker left by a killed agent blocks that one task until
  the reaper clears it.