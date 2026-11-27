# AGENTS.md - rules for agents working in this repository

This repository is worked by several agents across several machines. Read this
before your first edit.

## Scope

This repository is the fleet's environment setup - transport, workers, failover, audits, rules - and
deliberately contains nothing project-specific. Investigations, issue analysis and title findings live
with the project or in the coordinator's findings directory, never here. A project document added here
is a scope error. Lessons from a project run do belong: they are about method, and will name the project they came from.

## Your lane

- Work only in the worktree you were given, on the branch you were given.
- Never commit to the branch of record. Never push. Handoffs are bundles.
- One deliverable. If the brief is too broad to finish, say so before starting.

## The bar for "done"

- The change compiles: the repo's compile gate passes.
- The tests you added or changed pass on every backend the harness offers - and if
  a backend genuinely cannot run them, the skip is counted and an all-skipped run
  fails.
- One mutation you can name makes a test go red; you restored it and the tree is
  clean.
- Gates: format, lint, policy, your filter, one full run.
- You committed. A partial batch with named failures beats an empty branch; if the
  task cannot be done, commit a patch plus a note saying exactly where it broke.

## Reporting

Every report carries: commit hash, hardware adapter, driver version, toolchain,
wall time, exit code, pass/fail/ignored counts, and whether another test binary was
alive when you started.

A number without its commit is not a result.

## Never

- No pushing, no pull requests, no remote branches, no alternative account.
- No game/title/runtime captures, no dumps, no driver or OS changes.
- No installing anything; request it instead (see docs/fleet-playbook.md 10.9).
- No editing another lane's worktree, the channel, or files outside your worktree.
- No weakening a test to make a board green. Report the failure.

## Operating rules (adopted from the three-node lab, 2026-11-27)

Two rules the human set after they were broken in the lab. They are not stylistic; each one exists
because its absence lost work or caused unexplained drift.

### R1 - The coordinator owns the project files

No agent other than the coordinator writes into a project repository - no commit, merge, rebase,
reset or file edit. Changes are **suggested** to the coordinator in its share under `proposals/`.

A proposal names: what changes, why, which files, the evidence that it works, the risk, and how to
revert. Status is `proposed`, `accepted` or `rejected`; an accepted proposal records the resulting
commit ids, so the decision stays traceable. A proposal that cannot name its evidence is not ready.

Allowed without a proposal: read-only inspection, bundling (adds no repository content), records in
the coordinator's share, and documentation outside the project repositories.

This sits alongside, not instead of, this file's own lane rules: a lane still commits only in its
own worktree and still never pushes.

### R2 - Instruction updates are handled sequentially

Prompts from the user - on any workstation, in any session - are processed **in the order
received**. New input does not dismiss a previous request.

- Additional input while a request is in progress **queues behind it**; it is not a replacement.
- An earlier request is not abandoned, folded away or silently reinterpreted because a newer
  message arrived.
- Only an explicit cancellation - "nevermind", "drop that", "stop" - removes a request.
- A contradiction between a later and an earlier instruction is **reported**, with the earlier one
  completed or explicitly parked first. Never resolved silently.
- With more than one request outstanding, each result states which request it answers.

### R3 - Every rule and behaviour change reaches this repository

Any newly adopted rule, or any change to working behaviour, is written here **in the same pass it
is adopted**: the rule as an agent must read it in this file, the reasoning and history in
`docs/rules.md`.

- The running fleet's `RULES.md` and this file must not diverge. A rule present in only one of them
  is not adopted, it is proposed.
- Amend, don't append-only: when a rule changes, correct the old text in both places and record the
  correction.
- An agent may draft a rule; only the human adopts one - the same as accepted risks.

This repository is the part of a fleet that survives it. A rule learned in a run and not written
here is learned once and lost.

### R4 - A restart needs a named recovery path and the operator's agreement

Before restarting or rebooting a station, state how it comes back. A machine with no out-of-band access
(no IPMI, no console) cannot be recovered remotely if the boot fails, so that restart is a physical
intervention, not a maintenance action:

- Name the recovery path in the same breath as the intent: console access, a second admin channel, or
  someone physically present.
- Without a recovery path, ask the operator before restarting. Do not restart and hope.
- Scope: stations only. Fleet services this fleet owns (dashboard, feeder, reaper), the
  agent and the queue are not stations - restart or drain them as needed, naming the recovery
  path above. The failure R4 was written after cannot happen to a scheduled task that returns in
  one second.
- A station that is the coordinator deserves the strictest reading: if it does not return, the queue
  goes with it.

Evidence: a restart to repair a WMI provider was proposed without a way back, the station booted and
did not rejoin the network, and recovery waited for a human to walk to it. The restart was correct; the
missing recovery path turned it into an outage.

### R5 - A bundle is durable only off the machine that made it

Any bundle refresh writes the off-machine copy in the same pass, and the copy's tip is compared
against the source's - not assumed.

- "In the same pass" means the copy is part of the bundling step, not a later intention.
- Compare tips. A bundle that exists elsewhere but is older than the work it should carry is not a
  backup, and the staleness is invisible until the moment it matters.
- Throwaway snapshots are exempt; bundles that carry merged work are not.

Evidence: the bundle holding four merges existed only on the coordinator. When the coordinator went
down, the off-site copy was four merges stale. Recovery worked by luck, because the branch pointers
happened to survive inside the older bundle.

### R6 - Falsify before explaining

Before writing a fix, or reporting a cause, state the observation that would **disprove** it - and
obtain that observation first. A theory that has not been attacked is not ready to be written down.

- For a code change: name the test that fails without it, run that test against the old behaviour,
  and watch it go red before claiming it works.
- For a diagnosis: name the measurement that would contradict it, and take it before writing prose.
- A report that cannot say what would falsify it is a description, not a finding.

### R7 - Ask the question that separates two live hypotheses

When two explanations are both plausible, do not run more experiments that merely confirm either one.
Design the single observation whose outcome differs between them, and take that.

- Prefer one discriminating test over three confirming runs.
- Record both hypotheses and the expected outcome of each before the run, so the result is a decision
  rather than something to interpret afterwards.
- If no test can separate them, say so; that is a reason to instrument, not to keep reasoning.

R6 and R7 come from the 2026-11-27 session: a claimed `?`-operator bug survived review and was written
into a proposal, then died in one mutation test; and hours went to a fallback-descriptor theory that a
single per-draw run killed, because the question asked was "is it still black" rather than "do the
draws write here or elsewhere".

### R8 - A STOP file halts fleet automation

The operator stops the fleet's automation by creating a file. That is the switch: it needs no UI, no
session and no permission to be granted in advance.

- Checked before any state-changing action: starting or restarting an agent, seeding or clearing
  tasks, changing a share, a task or a credential, and any restart.
- Paths, first match wins: `STOP` beside the script, `C:\fleet\STOP`, `%USERPROFILE%\fleet\STOP`,
  `D:\fleet\STOP` (the coordinator share, so one file halts the whole fleet).
- A script that finds it exits non-zero and reports; it never proceeds and never silently skips.
- The file belongs to the operator. An agent does not create it, and does not delete it to resume:
  only the operator removes the stop.

Implemented by `scripts/guard-stop.ps1` (`-Status` reports where it looked).

Runtime approvals are a separate layer: when the application asks before privileged actions, that
gate is authoritative and a STOP file is no substitute for answering it.

### R9 - Publication authority

The auditor publishes to the repositories named in `PUSH-POLICY.md` and to no other. The allowlist
decides, not the credential: a token that can reach a repository does not make it eligible.
Everything outside the list is produced as a bundle and left for a human.

The original policy was local-only because no auditor existed to hold the judgement, following an
incident where an agent pushed another owner's branch into a fork. Amended by the operator on
2026-11-27 once the auditor was assigned: publishing gained a named owner and lost a blanket
prohibition.

### R9a - Requesting a change to a project we do not own

A change may be offered to `JMAN730/project-flamingo` or `Marvisak/VIctory` only when it is a proven
fix - it reproduces, it stops the problem, it does not break other things, it is explained, and it is
one problem per request - and only after the operator approves that specific request, one at a time.
Anything short of that is an observation: post it as a comment, never as a change request.

### Why these are written down

R1 followed four merges applied to a working line without asking; the coordinator could see the
files change and had no way to know why. R2 follows sessions where a later message absorbed an
unfinished earlier one, which loses work quietly and leaves no trace afterwards.

## Traps this fleet has already paid for

Each of these cost real time on 2026-11-27. Full evidence: `docs/lessons-2026-11-27.md`.

- **Validate config with its own parser before restarting a service.** A directive appended to the end
  of `sshd_config` landed inside a `Match` block and stopped sshd from loading at all.
- **Verify the artifact, not the attempt.** A script that aborted at step 2 never ran step 5; a later
  check reported the file existed, not what it contained.
- **Rotating a credential file does not rotate a running process.** Stop the service and kill the
  process, or the old password keeps retrying and locks the account.
- **Fail fast on auth errors, cool down on the rest.** Retries convert one bad password into a lockout.
- **Never claim a fix without watching the test go red.** A test that passes with the bug restored
  certifies a false explanation.
- **Absence is unknown, not health.** An idle queue is not an idle fleet; a missing file is not a missing
  producer - read the code before asserting one.
- **Convert symptoms into files.** A captured frame with `RGB(0,0,0)` outlives any description of a black
  screen.
- **Name the recovery path before a reboot** (R4, drafted) and **copy bundles off the machine in the
  same pass** (R5, drafted).