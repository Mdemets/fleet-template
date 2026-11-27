## 2026-11-27 (late) - adding a reasoning station costs nothing

- `docs/fleet-setup.md`: a free DeepAI account is the only requirement to give a new station a
  reasoning runtime - install, sign in once, done. No key, no per-seat licence.

## 2026-11-27 (late) - DeepAI Code is part of station provisioning

- `docs/fleet-setup.md`: new prerequisite - DeepAI Code on every station at one pinned version, signed
  in, with `127.0.0.1:3773/mcp` answering. Notes that the bundled `claude.exe` is the paid SDK and that
  the usual blocker is OAuth consent (`401`), not the install.
- `docs/fleet-playbook.md` 11.1: the golden image for a station now includes it.

## 2026-11-27 (late) - lessons from building the monitor

- `docs/lessons-2026-11-27-night.md`: the head-of-line deadlock caused by 46 stale claim markers, the
  watcher that prevents it, the 99.9% no-op discovery, the dashboard's own 20-second scan, the three
  incomparable numbers, role-based eligibility, and provisioning as staging rather than purchase.

## 2026-11-27 - pushing to other people's projects, in plain language

- `PUSH-POLICY.md` rewritten without jargon: copies are allowed, change requests are questions, and a
  request may go to `JMAN730/project-flamingo` or `Marvisak/VIctory` only when it is a proven fix and
  the operator approves that one request.
- The five-part test for "actual fix": reproduces, stops the problem, breaks nothing, explained, one
  problem per request. Anything short of it is a comment, not a request.
- `docs/rules.md` and `AGENTS.md` record the same rule in the same pass (R3).

﻿## 2026-11-27 - monitoring, task creation, measured throughput

- docs/monitoring.md - the four fleet figures, the four ways they lie (unit, window, clock, cache),
  why utilisation penalises the fastest station, and why claim residue is not work in flight.
- docs/task-creation.md - supply loop, caching the source so execution never blocks on a network
  call, batching for task duration, the high-water mark that actually sets queue depth, and why
  manufacturing load is the failure mode of "keep the fleet busy".
- docs/fleet-setup.md - sustained throughput measured on three stations replaces the single-burst
  figure as the headline, with both retained and labelled.
# Changelog

What changed, when, and why. Newest first. Measurements are from the fleet as it ran, not projections.

## Later on 2026-11-27 - the claim sidecar removed, and a monitor

- **Dropped the per-claim sidecar.** The claim marker in `locks/` already carries the claim time - it
  is created at claim and removed at completion - so `results/<node>/claims/<id>.json` was a redundant
  SMB write on every task. The reaper now ages a claim by its marker and keeps the sidecar only as a
  legacy fallback.
- **Measured:** 300 tasks in 7.5 s, mean **39.8 tasks/s** over three runs, 0 duplicates - against 31.6
  with 64 slots before the change.
- **Proven:** a claim whose marker is 30 minutes old is retried; a claim with a fresh marker is
  untouched. The old code would have aged the stale one as zero, because the claim file was created at
  test time - so this test fails without the change.
- Added `fleet-monitor.ps1`: a 5-minute health write to `status/health.json`, flagging stale
  heartbeats, stale claim markers, outstanding claims, and a queue that is not shrinking.
## 2026-11-27 - a working, parallel, hardware-independent fleet

**Transport**

- Pull-based share queue: `queue/`, `claimed/<node>/`, `results/<node>/`, `locks/`.
- Claim protocol upgraded from move-only to **create-exclusive marker + move**. Move alone allowed a
  peer to execute the same task twice (2 of 96 measured); the marker decides the winner first.
- Claim markers live in `locks/` because the worker accounts **cannot create files in `queue/`** -
  and a marker that cannot be created made every worker skip every task, silently.

**Parallelism**

- Replaced N worker processes with **one agent per station** (`scripts/FleetAgent.ps1`) driving a
  runspace pool. Child processes do not inherit a parent's network session; runspaces share the
  agent's process, and therefore its session.
- Measured: 300 tasks in 8.9 s (33.8 tasks/s) across three stations, 0 duplicates, 0 failures. The
  original single-worker, 30 s-poll arrangement managed ~0.03 tasks/s.

**Roles and sizing**

- `scripts/assess-fleet.ps1` measures an unknown fleet (cores, threads, RAM, share disk, address,
  static-ness, self-measured scaling) and recommends coordinator, worker slots and an auditor.
- `docs/fleet-sizing.md` states the decision rules and the measured scaling curves behind them.
- The auditor is a role with independence requirements, not a spare worker slot.

**Setup**

- `scripts/setup-transport.ps1` builds either role: share and directories, the `locks/` ACL grant,
  `coordinator.unc`, the reaper task, the agent task, and a verification step.
- `docs/fleet-setup.md` is the runbook, including the NetTCPIP `mofcomp` repair that a reboot does
  not fix.

**Governance**

- R1 coordinator owns project files; R2 instruction updates are sequential; R3 every rule reaches
  the template in the same pass; R6 falsify before explaining; R7 ask the question that separates
  two live hypotheses. R4 (name the recovery path before a reboot) and R5 (bundles durable
  off-machine) are drafted, awaiting adoption.
- `docs/thinking-protocol.md` carries the eight practices those rules came from.
- Scope: this repository is environment setup. Investigations live with their project.

**Fixed along the way**

- The `victory-gpu` stride-variant code path was unreachable when the base pipeline attempt had not
  run yet; fixed on a branch with a regression test that fails without the change.
- A stale `Atom::Opaque(_)` pattern left the app crate uncompilable (E0023) after another fix.

**Known limits**

- Runspaces share one process and heap: CPU-bound payloads behave like threads, not processes.
- A payload that kills the agent takes that station's slots with it until the reaper requeues.
- SMB pooling by separate processes remains unsolved and is no longer attempted.

## Credits

Built by the operator and an agent working together on 2026-11-27:

- **Operator - the operator**: owns the fleet, the project and every decision to change it; provided
  hardware, physical access, credentials custody, and the domain judgement (including stopping work
  that was heading the wrong way, and correcting the record when it was wrong).
- **Agent - DeepSeek v4.1 Flash in DeepAI Code**: designed and implemented the claim protocol, the
  station agent, the assessment and sizing procedure, the audits, the rules and the documentation;
  ran the measurements and the failure analysis.

The failures are documented as carefully as the successes - three of the four parallelism attempts in
this work were wrong before they were right, and `docs/lessons-2026-11-27.md` records each one with
its evidence so the next fleet starts further along.