# If you have multiple workstations at your disposal, set up the ultimate work fleet with this template :)

Most of us have two or three machines sitting half-idle. This template turns them into one pool that
answers for its work.

## What it does

One coordinator hosts a file queue; each station runs a small agent that pulls tasks, runs them in
parallel inside a single process, and writes results back. A reaper retries stale claims and records
dead ones. Nothing needs a cloud, an account, or internet access - just SMB access to the coordinator.

## Measured, not promised

Three stations, 32 task slots: **300 tasks in 8.9 s (33.8 tasks/s), zero duplicates, zero failures.**
The arrangement it replaced - a single worker polling every 30 seconds - managed about 0.03 tasks/s.

The measurement that matters most is the one people skip: results grouped by station. Three times
during development the coordinator quietly covered for broken workers, and a burst that reported only
"drained N/N" hid every one of those failures.

## What is in the box

- Setup scripts for either role: coordinator or worker.
- A sizing tool that measures *your* fleet and recommends roles and slot counts from the numbers.
- A prerequisite checker that gates a candidate station with PASS/FAIL per requirement.
- Coordinator failover, four audits, and a reboot-recovery helper.
- The rules that came out of the incidents, each with the measurement that produced it.

## What is not required

Same subnet. Administrator access at run time. Matching hardware. A GPU. The template was written on
one fleet and is deliberately independent of it - start with `docs/fleet-minimums.md`.

## Why it exists

It grew out of trying to run a demanding Windows title natively across several workstations. Which is
to say: it exists because of two projects that had nothing to do with fleet tooling.

- [Marvisak/VIctory](https://github.com/Marvisak/VIctory) - the upstream effort that gave this work
  something worth testing.
- [JMAN730/project-flamingo](https://github.com/JMAN730/project-flamingo) - the working fork where the
  multi-station work happened and where most of the transport's requirements were discovered.

Their conventions became the rules here: *a number without its commit is not a result*, *one mutation
must go red*, *one writer per branch*, *the coordinator owns the code*. Credit to both, and to the
people who write reports with real numbers in them - measurement dossiers are rare and far more useful
than opinions.

## The template

https://github.com/Mdemets/ai-workfleet-template

If you would rather thank the upstream projects than use this, star those two repositories. That is the
honest exchange.

---

*Please share this by linking it. Pasting a template link into someone else's issue tracker is spam by
most maintainers' definition, and it would reflect badly on the projects credited above.*