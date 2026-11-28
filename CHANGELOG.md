## 2026-11-28 - draft: intent to work

- `docs/draft-intent-to-work.md`: the six-stage chain from operator prompt to executed unit, with the
  unit schema (question, evidence, command, `done_when`, resource, requeue), the two gates, the explicit
  stop condition, the four-field failure taxonomy drawn from tonight, and the three things still missing.

## 2026-11-28 - the watcher line names what it watches

- `fleet-dashboard.ps1`: the watcher line now ends with `monitoring <repo>, <repo>`, read from the keys of
  `status/repo-etags.json` - the same file the watcher uses for its ETags, so the list cannot drift from
  what is actually polled.
## 2026-11-28 - the scope reads as an assignment and a question

- `fleet-dashboard.ps1`: `status/scope.txt` may hold several lines. The first is the assignment and reads
  as the scope; every further line is shown below it, dimmed and italic - so the operator question that
  started the work sits on its own line instead of trailing the description.
## 2026-11-28 - the repo watcher counts what it finds, and shows it is alive

- `FleetRepoWatch.ps1`: a discovery window opens when a poll finds new issues. `discovered` counts topics
  found and waiting; it resets to **0** the moment they are pulled in as tasks, while `reported` keeps the
  window total. The window closes after ten quiet minutes. `lastPoll` / `lastResult` are written every run.
- `fleet-dashboard.ps1`: the scope line now carries `watcher: active | stale`, how long ago it polled,
  pending topics, and how many were reported this window - so a silent watcher is visible instead of
  looking like a quiet repo.
- The `since` filter was removed: it changed the URL on every poll, which makes a 304 impossible and spent
  quota for nothing. With a stable URL and the stored ETag, an unchanged repo answers 304 and costs zero.
## 2026-11-28 - the board states its scope, and the console moves up

- `fleet-dashboard.ps1`: a **scope line** at the top of the page, read from `status/scope.txt`, states the
  assignment currently being worked - the question that started the activities - so a screenshot of the
  board carries its own context. The console input sits directly beneath it, at the top, instead of at
  the bottom of a long page.
- `FleetDashboardRestart.ps1`: starting the monitor now also triggers the repo watcher and one queue
  monitor pass, so a redrawn board checks for new work immediately rather than at the next tick.
## 2026-11-28 - the activity panel is a switch, not a drag

- `fleet-dashboard.ps1`: the minimise/maximise buttons that lived inside the activity rail are gone. A
  single **activity: on/off** switch sits outside the panel, above the controls, and hides or shows it
  entirely - the page reflows to full width instead of leaving a column-sized gap.
- The control row's click handler is scoped to `#ctl button[data-cmd]`, so decorative buttons cannot
  inherit a fleet command. That scoping bug is what made the first version of the switch inert.
## 2026-11-28 - station state colours and a guarded reboot switch

- `fleet-dashboard.ps1`: station icons show heartbeat age (green <60 s, amber <180 s, red beyond) and a
  hover power switch. Rebooting writes `control/reboot/<node>.json` with an explicit confirmation marker;
  the coordinator additionally requires the word REBOOT typed.
- `FleetAgent.ps1`: claims nothing while a reboot request stands for its node - that is the drain.
- `FleetWatchdog.ps1`: restarts only when the node reports zero running tasks, ignores unconfirmed
  requests, and removes requests older than 30 minutes without acting.
- `docs/lessons-2026-11-27-night.md` section 11: the test that rebooted the coordinator, and the three
  rules that came out of it.
## 2026-11-28 - a repo watcher that costs nothing when nothing changed

- `scripts/FleetRepoWatch.ps1` (new): polls both repositories every 10 minutes with a stored `ETag` and
  `since` filter. An unchanged repo answers `304`, which GitHub does not charge against the rate limit -
  measured: two polls, zero requests counted. A changed repo is merged into the corpus incrementally and
  signals an immediate refill.
- `scripts/FleetQueueMonitor.ps1`: guarantees a refill at least every 10 minutes, held whenever the
  operator has paused or drained - verified both ways in the log.

Bug found while applying it: PowerShell wrapped the 50-issue JSON array as a single item, so one
"issue" became the whole list and four corpus entries were written with the list in the number field.
Fixed by enumerating explicitly, and the four entries were repaired out.
## 2026-11-28 - a hard exclusion, and what it overrides

- `PUSH-POLICY.md`, `docs/rules.md` (R9b) and `AGENTS.md`: **no Project Leonida artefact is ever published
  online** - source, builds, logs, analysis, measurements, screenshots. Local only, permanently.
- Audit at the time of writing: zero Leonida files on the share, zero references in this repository, so
  nothing needed retracting.

## 2026-11-28 - FleetWatch, the operator console, and a queue that cannot dead-end

- Renamed the monitor page to **FleetWatch** (`fleet-dashboard.ps1`), with station icons, click-to-filter
  rows, and a console box that queues messages to the agent thread.
- New `scripts/FleetQueueMonitor.ps1`: per-minute queue and supply line, low-water refill, and an
  exhausted-supply alert that cannot be confused with a fault.
- New `scripts/FleetCorpusFinder.ps1`: dispatches from a cached, authenticated corpus so no task needs
  the network at run time - replacing a source whose tasks failed 99.9% of the time.
- New `scripts/FleetWatchdog.ps1` and `scripts/FleetFeeder.ps1`; updated `scripts/fleet-dashboard.ps1`
  with the control endpoint (refill/pause/resume/drain/alarm), token-checked.
- Lessons that produced these changes: `docs/lessons-2026-11-27-night.md`.
- The old issue-scraping finder is deliberately **not** shipped: it dispatched tasks that fetched at run
  time and failed 99.9%. `FleetCorpusFinder.ps1` supersedes it.

## 2026-11-27 (late) - the monitor has a picture

- `docs/images/monitor.png`, referenced from `docs/monitoring.md`: the board as it ran, with a station
  selected so the filtering is visible.

## 2026-11-27 (late) - credit for free AI to the people

- `CREDITS.md`: DeepAI Code credited in the operator's words for offering an awesome tool *and free AI
  to the people* - a desktop app with working models, no trial, no teaser.

## 2026-11-27 (late) - free tier means lowest priority, not an outage

- `docs/fleet-setup.md`: records that a free account is served behind paid traffic - a latency
  property, not availability - and what follows from it: asynchronous calls, generous timeouts, never
  on an interactive path. No downtime in this run was attributable to the provider.

## 2026-11-27 (late) - two reboots, one of them a hang

- `docs/lessons-2026-11-27-night.md`: mdma had a hang-and-reboot (boot 11-26 10:04) alongside the
  coordinator's planned restart. Both recovered unattended; the distinction matters, because a hang
  leaves no log line and points at the GPU stack or memory pressure rather than the fleet software.

## 2026-11-27 (late) - the coordinator rebooted and the fleet did not notice

- `docs/lessons-2026-11-27-night.md`: records the coordinator reboot (boot 15:24), the clean recovery of
  share, workers and schedules, and the age arithmetic - ~100 station-hours versus a ~9.5-hour continuous
  window. Quote which clock.

## 2026-11-27 (late) - the 100-hour milestone, measured honestly

- `docs/lessons-2026-11-27-night.md`: uptime ~100 h against ~30 useful tasks out of 38,000 executed.
  The point recorded is that uptime is the least interesting number a fleet produces; the failure mode
  that matters is continuing cheerfully while doing nothing.

## 2026-11-27 (late) - credit where it is due

- `CREDITS.md`: DeepAI Code credited for offering an awesome tool, in the operator's words - the piece
  that turned three spare machines into a fleet that could notice its own failures.

## 2026-11-27 (late) - DeepAI Code credited as the free reasoning runtime

- `CREDITS.md`: a section crediting DeepAI Code - the free runtime the fleet's reasoning lane runs on,
  and the source of the models named above. Recorded as a current dependency with an exit path.
- `docs/fleet-setup.md`: the same statement where station setup is described.

## 2026-11-27 (late) - the free dependency is stated, not assumed

- `docs/fleet-setup.md`: records that the reasoning lane currently runs on DeepAI Code *because it is
  free* - a present fact with an exit path, not a permanent assumption. If it stops being free, the
  transport and workers are unaffected; only reasoning degrades.

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