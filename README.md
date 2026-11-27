# AI Workfleet Template

Environment setup for a small fleet of Windows machines that run work in parallel and are answerable
for what they do: one coordinator hosts a file queue, every station runs an agent that pulls from it,
and a reaper keeps claims honest. It is deliberately independent of the hardware it was written on and
of the project it was first used for.

## Current state (measured)

| Station | Role | Slots | Share access |
|---|---|---|---|
| node-a | coordinator + worker | 16 | local path |
| node-b | worker | 8 | `\\<coordinator>\fleet` |
| node-c | worker | 8 | `\\<coordinator>\fleet` |

**300 tasks in 8.9 s (33.8 tasks/s), 0 duplicates, 0 failures.** The arrangement that preceded this
one - a single worker polling every 30 s - managed about 0.03 tasks/s.

Those numbers are from three specific machines. Nothing in the scripts assumes them: `assess-fleet.ps1`
re-derives roles and slot counts from whatever fleet you point it at.

## How it works

    coordinator                         workers
    -----------                         -------
    share/queue/task-*.json   <--pull--  agent claims: create ../locks/<task>.claim, then move
    share/claimed/<node>/     --------->  runs the payload in a runspace pool
    share/results/<node>/     <---------  writes result-<id>.json + claims/<id>.json sidecar
    share/results/<node>/heartbeat.json   {node, ts, active}
    share/reaper.log                      a janitor retries stale claims, records dead tasks

Three decisions carry the design:

1. **A claim is an exclusive create, not just a move.** Move alone let two nodes execute the same task
   (2 of 96 measured). The marker decides the winner before any move happens.
2. **Parallelism is a runspace pool inside one agent process.** A child process does not inherit its
   parent's network session - three designs failed that way - while runspaces share the agent's.
3. **Claim markers live in `locks/`, which the worker accounts may write.** `queue/` refuses their
   creates, and a marker that cannot be created makes a worker skip every task silently.

## Bring a fleet up

| Step | Command | What it gives you |
|---|---|---|
| 1. size it | `scripts/assess-fleet.ps1 -Hosts a,b,c` | roles, slot counts, an auditor recommendation |
| 2. gate it | `scripts/check-prerequisites.ps1 -Coordinator <addr>` | PASS/FAIL per requirement, non-zero exit on failure |
| 3. coordinator | `scripts/setup-transport.ps1 -Role coordinator -SharePath <path> -Accounts <names>` | share, directories, `locks/` ACL, reaper task |
| 4. worker | `scripts/setup-transport.ps1 -Role worker -CoordinatorUnc \\<addr>\fleet -Node <name> -Slots <n>` | agent deployed, startup task, verification |
| 5. prove it | a burst sized to the slot total | **per-node distribution**, not just the drained count |

Step 5 is not ceremonial. Three times in this fleet's development the coordinator covered for broken
workers: 300 tasks drained, all done by one machine, nothing in the logs. Per-node numbers are the only
signal that catches it.

## Rules an agent must follow here

| Rule | Content |
|---|---|
| R1 | The coordinator owns the project files; changes are proposed, not applied |
| R2 | Instruction updates are handled sequentially; new input never dismisses an earlier request |
| R3 | Every rule and behaviour change reaches this repository in the same pass it is adopted |
| R4 | A restart needs a named recovery path and the operator's agreement |
| R5 | A bundle is durable only off the machine that made it |
| R6 | Falsify before explaining: obtain the disproof before writing a cause or a fix |
| R7 | Ask the question that separates two live hypotheses instead of running more confirming tests |

R4 and R5 guard against rare but expensive events: a restart with no way back, and a bundle that only
exists on the machine that made it. `AGENTS.md` is the full text; R6 and R7
came from `docs/thinking-protocol.md`.

## What is in here

    AGENTS.md              the rules an agent working in this repository must follow
    CHANGELOG.md           what changed and why, with the measurements
    CREDITS.md             who and what produced this, including the failed attempts

    docs/fleet-setup.md    the bring-up runbook and verification checks
    docs/fleet-sizing.md   how to assign roles and slot counts from measurements
    docs/fleet-minimums.md what a station needs to join, and what disqualifies it
    docs/fleet-playbook.md the long write-up: loop, faults, least privilege, provisioning
    docs/rules.md          the rules as adopted, with their evidence
    docs/thinking-protocol.md  eight practices for spending effort on evidence
    docs/auditor-role.md   the auditor's contract, limits and independence requirement
    docs/lessons-2026-11-27.md  twenty-one lessons, each with the measurement that produced it

    scripts/setup-transport.ps1     build either role on a station
    scripts/FleetAgent.ps1          the station agent (one process, runspace pool)
    scripts/FleetWorker.ps1         single-task worker, the fallback and the claim reference
    scripts/Invoke-FleetReaper.ps1  claim ageing, dead tasks, pruning
    scripts/assess-fleet.ps1        measure a fleet, recommend roles and slots
    scripts/check-prerequisites.ps1 gate a candidate station
    scripts/audit-*.ps1             fleet, station, coordinator and efficiency audits
    scripts/fleet-failover.ps1      move the coordinator between stations
    scripts/recover-after-reboot.ps1, bundle*.ps1, doctor.ps1, watch.ps1, pull.ps1, post.ps1

    agents/                copy-paste briefs: lane, station message, incident
    config/                machine-readable manifests (environment, execution allowlist)

## Scope

This repository is **environment setup**: how to build, run and audit a fleet, independent of what the
fleet works on.

- **Belongs here:** transport, credentials, agent and reaper design, failover, audits, rules, and
  lessons about running machines.
- **Does not belong here:** anything specific to one project - investigations, issue analysis, a
  title's input route, render findings. Those live with the project.
- Lessons derived from a project run **are** welcome: they are about method, and they will name the
  project that produced them. The *investigation's output* belongs with the project; the *lesson about
  how it was run* belongs here.

## Announcement

ANNOUNCEMENT.md is the shareable write-up: what this does, the measured numbers, and the credit to
the upstream projects that made it necessary.

## Credits

docs/provenance.md records where the work came from and what it owes the two upstream projects that
made it necessary.


See `CREDITS.md` - the operator, the agent, the stations and their hardware, and which design each
failed attempt eliminated.

## What this is not

Not a framework, not a service. Files and scripts you run yourself. The scripts are PowerShell because
the reference fleet was Windows; the rules are portable.