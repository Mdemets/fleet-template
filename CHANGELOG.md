# Changelog

What changed, when, and why. Newest first. Measurements are from the fleet as it ran, not projections.

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