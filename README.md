# fleet-template

A reusable skeleton for running one codebase across several machines with several
agent lanes, a coordinator, and a rule that only verified work lands.

It is the working distillation of a 24-hour run: see docs/fleet-playbook.md for the
faults, the fixes, and the reasoning. This repository is the part you copy.

## What is in here

    docs/fleet-playbook.md     the full write-up: loop, rules, 17 faults, least privilege, provisioning
    AGENTS.md                  the rules an agent working in this repo must follow
                               including R1 (the coordinator owns the code; changes are proposed)
                               and R2 (instruction updates are handled in order, never dismissed)
    docs/rules.md              the same two rules as adopted and lived in the three-node lab
    agents/                    copy-paste briefs: lane, station message, incident
    config/                    machine-readable manifests (environment, execution allowlist)
    scripts/                   transport, sampler, bundler, doctor, provisioning skeleton

## Instantiate in five steps

1. Copy this directory into your project (or use it as the repository root and add
   your code under it).
2. Fill in config/env-manifest.example.json with the toolchain, SDK and driver
   versions you pin, and config/allowlist.example.json with what a lane may run.
3. Put the channel folder outside the repository (inbox, handoff, findings,
   outbox). Point scripts there with FLEET_CHANNEL.
4. Create the accounts from the playbook section 10.2 (provisioner / station /
   lane / test) and apply the ACLs. Run scripts/provision-station.ps1 only as the
   provisioner, once per image.
5. Start the sampler (scripts/watch.ps1) as a scheduled task, and a coordinator
   check every 10 minutes that reads its log.

## The five rules everything else follows from

1. One writer per branch; one deliverable per lane.
2. A count only means something next to its commit, with adapter, driver and
   "other test binary alive at start".
3. Nothing merges on a compile check alone: the changed tests run on both
   backends, and one mutation must go red.
4. A lane commits or explains. Zero commits is a process failure.
5. The GPU has one owner at a time, enforced by the harness, not by good manners.

## Credits

See CREDITS.md - the models, stations and human behind this template, and which kind of lane each model turned out to be good at.

## What this is not

Not a framework, not a service. Files and scripts you run yourself. The scripts are
PowerShell because the reference fleet was Windows; the rules are portable.

## Session records

What happened, what was measured, and what changed as a result:

| File | Content |
|---|---|
| `docs/lessons-2026-11-27.md` | retrospective: 16 lessons with their evidence, plus the rules adopted and drafted |
| `docs/incident-2026-11-27-reboot.md` | the coordinator reboot that did not return, and the restore |
| `docs/coordinator-primary-standby.md` | primary/standby arrangement and the credential rule that makes failover cheap |
| `docs/auditor-role.md` | the auditor's contract, limits, and change-record duty |
| `docs/rules.md` | R1-R3 adopted, R4-R5 drafted |
## Scope of this repository

This template is **environment setup**: how to build, secure, run and audit a fleet, independent of
what any fleet works on.

- **Belongs here:** transport, credentials, worker and reaper design, failover, audits, rules, lessons
  about running machines, and the thinking protocol.
- **Does not belong here:** anything about a specific project - investigations, issue analysis, a title's
  input route, render findings. Those live with the project or in the coordinator's findings directory.
- Lessons derived from a project run **are** welcome here. They are about method and machines - a
  mutation test that exposed a wrong explanation, a timer that looked like a deadlock - and they will
  naturally name the project they came from. That is the template learning, not the project documenting
  itself.
- Adding a project document here is a scope error, not a scope extension: the *investigation's output*
  belongs with the project, the *lesson about how it was run* belongs here.


## Bringing a fleet up

`docs/fleet-setup.md` is the runbook for the arrangement as measured on 2026-11-27:
coordinator on a local path, one agent per station with a runspace pool, claim markers in a
`locks/` directory the worker accounts can write, and the verification checks that catch a
silently idle station.

    scripts/setup-transport.ps1 -Role coordinator -SharePath D:\fleet -Accounts 'fleet-worker-b','fleet-worker-c'
    scripts/setup-transport.ps1 -Role worker -CoordinatorUnc \\<coordinator>\fleet -Node <node> -Slots 8

`scripts/FleetAgent.ps1` is the station agent (one process, runspace pool). `scripts/FleetWorker.ps1`
is the single-task worker, kept as the fallback and as the reference for the claim protocol.
## Sizing a new fleet

Nothing in this template assumes the hardware it was written on. Measure the fleet you have, then assign
roles from the measurements:

    scripts/assess-fleet.ps1 -Hosts <station1>,<station2> -AuditorHost <host outside the fleet>

It reports cores, threads, RAM, share disk, address, static-ness and self-measured scaling, then
recommends a coordinator (stability and storage), workers with slot counts (interpreter-bound vs
compiled), and an auditor that is independent of what it audits. The reasoning and measured scaling
curves are in docs/fleet-sizing.md.


## Current state (measured 2026-11-27)

| Station | Role | Slots | Share |
|---|---|---|---|
| node-a | coordinator + worker | 16 | local `D:\fleet` |
| node-b | worker | 8 | `\\10.0.0.10\fleet` |
| node-c | worker | 8 | `\\10.0.0.10\fleet` |

300 tasks in 8.9 s (33.8 tasks/s), 0 duplicates, 0 failures. The auditor runs outside the fleet with
read-only share access. `scripts/assess-fleet.ps1` re-derives these roles and slot counts from any
fleet's own measurements.