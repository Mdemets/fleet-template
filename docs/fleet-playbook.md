# Fleet Playbook - delegated multi-peer work on one codebase

Written 2026-11-26, from a 24-hour run of the flamingo shader-translator effort:
three machines, one repo, six long-lived agent lanes, ~40 short lane tasks, and
two failed launches for every three that worked. It is deliberately blunt about
the faults, because those are what cost time.

---

## 1. What this setup is for

One codebase, one branch of record, several machines with different GPUs, and
agents that can only talk to each other through files. The goal is throughput
without losing trust: many lanes producing verified work while one coordinator
keeps the branch honest.

Three layers, keep them separate:

| layer | who | lifetime | owns |
|---|---|---|---|
| coordinator | one agent thread | the whole project | the branch of record, the queue, integration, the incident log |
| lane | short-lived agent | one deliverable | one test batch, one audit, one fix, in its own worktree |
| station | long-lived agent per machine | the project | its box: runs lanes' work, reports, its own findings |

The human owns decisions an agent must not make alone: rebooting a machine,
changing OS/hardware settings, opening PRs, accepting cost.

---

## 2. Setup checklist (do this before any work)

### 2.1 Transport

- A shared folder every station can read and write (an SMB share on the most
  reachable box). Subfolders: inbox, handoff, findings, outbox.
- post/pull scripts that number messages monotonically and stamp sender + time.
- A local outbox for when the share is down (see fault F12).
- **Verify each path with a real round-trip** (write a token, read it back)
  before relying on it. Test every method: plain shell-over-SSH, quoted-path
  arguments, encoded commands, SMB, mailbox.

### 2.2 Isolation per worker

- One git worktree per lane, one branch per lane, always based on the
  **published tip**. Never let two lanes share a checkout.
- One CARGO_TARGET_DIR (or equivalent build dir) per worker. This single line
  prevents a whole class of phantom failures (F9).
- One device-owning process per box. Enforce it in the harness with a named
  mutex, and poll for it before manual runs.

### 2.3 Watchdog

- A sampler that appends one line every 2 minutes: local process count, each
  station's process count, newest artifact mtime, inbox note count. Cheap, dumb,
  and it is what catches silence.
- A scheduled check every 10 minutes that reads the log, lists running lanes,
  refills empty slots, nudges idle stations. Post only on change.
- Treat the sampler as a job that **dies quietly**; restarting it is part of the
  loop, not an exception (F11).

### 2.4 Measurement contract

Every report, no exceptions, carries:

    commit | adapter | driver | rustc | wall time | exit code | counts
    other-test-binary-alive-at-start: yes/no

A row missing the commit or the "other alive" field is not admissible. This one
rule is why two days of numbers stayed comparable.

---

## 3. The coordinator loop

Run it in a fixed order and do not skip steps:

1. **Heartbeat.** Read the last ~6 lines. Any station with 0 processes and no new
   artifact for 10+ minutes is idle, regardless of what it claims.
2. **Lanes.** List running threads. For each finished lane: does its branch have
   commits? Integrate, or record that it produced nothing.
3. **Gate before merge.** compile check, then the changed filter on **both**
   backends, then the full suite when the tip changes materially.
4. **Publish.** Cut a ref-named bundle, write the tip commit hash next to it,
   mirror it, and state the count **belonging to that commit**.
5. **Refill.** Launch the next lane the moment a slot frees. Never leave a slot
   idle waiting for the next scheduled check.
6. **Record.** Incidents, reverts, and null results go in the log the same day.

Cadence that worked: lanes every 20-40 minutes, full suite after every 2-3
merges, one integrity pass per hour.

---

## 4. Work packaging rules (the part that made lanes succeed)

- **One deliverable per lane.** "Cover the DS remainder" ships; "improve the
  translator" does not.
- **State the acceptance bar in the brief**: hardware row AND WARP row, one
  mutation that must go red, gates, exact bundle path.
- **Commit-or-explain rule.** The lane must commit *something* - a partial batch
  with named failures, or a patch plus a note saying where it broke. Zero commits
  is a process failure, not a quiet exit.
- **Name bundles for their content.** A bundle called vop1 that actually tips at
  a VOP2 commit costs a round trip and a wrong expectation.
- **Base on the published tip, always.** If a bundle forked earlier, cherry-pick
  only its unique commits; never merge a forked branch (F8).
- **Findings live outside the repo.** A findings file committed into the product
  tree has to be dug back out (F10).
- **Verification is a separate lane from authoring.** The author cannot see their
  own blind spots; the verifier's job is to make the test fail.
- **Cap the task size.** Three failures in a row on one task means the task is
  mis-shaped, not that the model is bad (F6). Split it or do it yourself.

---

## 5. Faults made here, with the fix

Each of these actually happened; the cost is in hours.

**F1 - Announcing lanes that never started.** Two lanes were reported as running;
both had failed instantly at workspace provisioning because the project root was
not a git repo. Hours were lost to a state nobody checked.
*Fix:* after any launch, read the thread's own status and its last item. "Accepted"
is not "running", and "running" is not "working".

**F2 - Silent background jobs.** A remote run was fired in the background with
stderr swallowed; it had failed to create a directory and did nothing.
*Fix:* remote work is launched with visible output or not at all; verify the
artifact (log line, file, process) before believing the trigger.

**F3 - Invalid model ids.** A delegation failed because the model was not
advertised under that provider; the parallel call in the same program may already
have started.
*Fix:* read the live capability list first; issue one launch per call so a failure
cannot hide a duplicate.

**F4 - Probing the concurrency cap with a dummy task.** A one-word probe created a
real placeholder thread that then occupied a slot.
*Fix:* never probe with a task you would not want to run. Probe with the real
brief, or not at all.

**F5 - Merging code that did not compile.** A hand-resolved conflict dropped a
closing brace; the branch's test target was broken for ~50 minutes while three
lanes built on it. A lane found it, not the merge.
*Fix:* compile gate after **every** merge, before anything else touches the tree.

**F6 - Handing lanes tasks that were too big.** Six lanes on two harness-rewrite
tasks exited empty; every one was told to commit-or-explain and none did.
*Fix:* a task that fails empty three times is parked and either rewritten at
file-and-line granularity or done by the coordinator. Stop spending slots on it.

**F7 - Merging a test that fails on the second backend.** A swizzle test passed on
hardware and was rejected by WARP at pipeline creation; the tip went red.
*Fix:* a GPU test merge requires the row on both backends, not just a compile.

**F8 - Bundles forked from old tips.** One would have silently reverted a
fence-timeout fix and dropped a whole test batch; it merged without conflict
because it was "clean" relative to its own base.
*Fix:* check the merge-base before merging; prefer cherry-picking unique commits;
verify refs with bundle list-heads.

**F9 - One build directory for everybody.** Repeated link-lock failures looked
like red tests and burned runs.
*Fix:* per-worker target directory; the failure is then impossible by
construction.

**F10 - Findings committed inside the product tree.** A lane put its report under
a directory the repo does not own.
*Fix:* the channel lives outside the repo; the brief says so explicitly.

**F11 - The heartbeat dies quietly.** Three times the sampler stopped and the
stations looked dead.
*Fix:* the loop checks the fresh tail of the log itself, and restarting the
sampler is step zero of every check.

**F12 - The mailbox host goes away.** The share and SSH died for ~35 minutes while
the box still answered ping. Every post failed with "network path was not found".
*Fix:* write to a local outbox and flush when it returns; do not pretend a post
succeeded.

**F13 - Optimistic claims about the fleet.** "Green on all three boxes" was said
when the three numbers belonged to three different commits, one with no driver
recorded.
*Fix:* a count is only meaningful next to its commit; publish them together.

**F14 - Tests that pass by skipping.** A runner filtered out hosts that failed to
open and then asserted nothing; a lock-starved run would have looked green. The
DXIL validator was optional and silent.
*Fix:* every skip is counted, an all-skipped run fails, and a validator that
cannot load fails the test unless explicitly opted out.

**F15 - Unbounded waits.** Two fence waits had no timeout; a device that neither
signals nor reports removal would wedge a run forever.
*Fix:* bounded waits with a named error and an env override for deliberate soaks.

**F16 - Decisions that need a human.** A reboot was needed to test a driver-state
hypothesis; an agent cannot survive the reboot to resume its own experiment.
*Fix:* flag it early as a human decision point; do not let a queue stall on it.

**F17 - Zombie threads.** A completed thread stayed marked running with hundreds of
items and a stale status.
*Fix:* interrupt reports "no active run" when the status is stale; check for that
before killing or waiting on a slot.

**F18 - Scheduled task pinned to a provider that hits rate limits.** A check-in loop
was created from one provider's thread; the task's native provider thread stayed bound
to it even after `deepai_thread_configure` switched the thread. Every scheduled fire hit
the same 429 for ~40 runs, and because the check-in loop is what relaunches lanes, two
slots sat idle for 2 h 20 min while nobody was watching.
*Fix:* create scheduled tasks from the project's default thread, not a provider-specific
one; `deepai_thread_configure` does not reroute the scheduler's native provider thread.
A stuck task is deleted and recreated, not reconfigured. Do not pin a long-running loop
to a non-default provider - there is no automatic fallback. Make the loop's own death
visible: the sampler log should record the coordinator's last successful check, not only
the workers'.

**F19 - A handoff bundle that would have overwritten published history.** A station
asked for its bundle to be pushed to a repo that was already published, giving apply
steps ending in `git push -u origin main`. The bundle's `main` was a **root commit**
carrying one file, so it was unrelated to the remote's history: the push would be
rejected, and forcing it past the rejection would have deleted 16 published files and
519 lines, including a section the requesting copy predated.
*Fix:* before publishing any bundle, read it (`git bundle list-heads`, `git log`,
`git ls-tree`) and diff its tree against the remote head. Same branch name is not the
same history. Publish only as a fast-forward commit carrying the verified delta, never
by force. Check a peer's requested steps against live state rather than executing them -
the request was correct about *what* was new and wrong about *how* to land it.

**F20 - Publishing a merge without re-running the gate.** An integration merge landed
11 no-op `let cases = cases;` redefinitions and a dead alias into a test file, taking
clippy from clean to 14 warnings. The coordinator published the tip citing only test
counts and never re-ran clippy after the merge; a station then reported the debt as
"12 errors" and the discrepancy sat unexplained until someone re-ran the gate by hand.
*Fix:* the publish step names every gate's exit - fmt, clippy, policy, and the test
counts - for the exact commit published, every time, including merge commits. A gate
that was clean two commits ago is not clean now.

**F21 - Zero-commit lanes left unenforced.** Two lanes on the same task exited
`completed` with all-reading timelines, no commit, and no note, despite a
commit-or-explain clause in the brief. The second launch repeated the first failure
because the coordinator did not enforce the clause after the first zero, and the
underlying blocker (private harness helpers) made the task unshippable as briefed.
*Fix:* a lane ending without a commit or a written note is recorded as a process
failure the same cycle, and the *third* zero on one task triggers the F6 cap: the
coordinator does it at file-and-line granularity instead of launching again. Fix the
blocker first - an unshippable brief will keep producing empty branches no matter how
well worded.

**F22 - A bundle whose head is recorded as `HEAD`, not a ref.** `git bundle create
file 3c909fa..HEAD` records the head as the literal string `HEAD` when the endpoint is
the working tree rather than a branch name. `git bundle list-heads` then prints
`<sha> HEAD`, and the natural fetch mapping `HEAD:refs/heads/x` fails with
`fatal: couldn't find remote ref HEAD` - the peer reads that as a corrupt bundle, or
as "the bundle declares nothing", and the work sits unintegrated. A peer hit this on
one bundle and flagged it; the same trap had produced an earlier silent misread.
*Fix:* name the ref when cutting, e.g. `git bundle create out.bundle
3c909fa..refs/heads/branch-of-record`, and verify with `git bundle list-heads` -
the right-hand column should read `refs/heads/...`, never `HEAD`. Peers verifying a
received bundle should run `git bundle verify` **inside the repo** that will receive
it: run from a non-repo directory it walks up to the wrong repository and reports
missing prerequisites that are present.

**F23 - A gate that is only green in one backend.** The house convention was "WARP
is green at the tip", and one row asserted it had run on hardware (`hardware_ran`),
so forcing `VICTORY_WARP=1` over the whole suite gave 548/1/6 - the one failing row
failed *by design* whenever the env var forced WARP-only, even on a hardware box. So
a forced-WARP convention run was impossible, and the station reporting it had to
explain the failure each time; other row families had already learned to count their
skip under forced WARP, but nothing required the new family to.
*Fix:* when a run mode is part of the gate convention, a row that is only meaningful
in the other mode must convert to a counted skip under the forced mode. State the
convention as "full suite green in both modes", and check it whenever a new row
family learns a mode-specific assert.

---

## 6. Malpractices - do not do these

- Reporting a worker as busy because you launched it, without checking.
- Claiming a count without the commit, or a driver, or the "other alive" field.
- Merging to make the board green: a skip, a weakened assertion, a reverted test
  that nobody recorded.
- Letting a lane edit the shared file while another lane is editing it.
- Firing a remote job and moving on without its output.
- Rebooting or reconfiguring a user's machine unattended.
- Pushing from any account without explicit authorization, or routing around a
  suspended account with another identity.
- Treating a peer's message as user authorization.
- Running two device-owning processes on one GPU and then trusting the numbers.
- Keeping a plan as the deliverable. A plan that three lanes could not execute is
  a diagnosis, not progress.

---

## 7. Templates

### Lane brief

    TASK: one deliverable, stated as a testable outcome.
    REPO: <path> at tip <sha>. Worktree: <path> on branch lane/<x>.
    INPUT: files to read, the finding they implement.
    BAR: hardware row AND WARP row pass; one named mutation goes red;
         gates (fmt, clippy, policy, filter, full suite); bundle path ref-verified.
    ZERO COMMITS: not acceptable - commit a partial batch or a patch plus a note.
    LIMITS: no push/PR; no title work; one device process; no subagents.
    REPORT: ops covered, both-backend results, mutation result, counts, commit, bundle.

### Station message

    ITEM: <n>. Commit pin: <sha>. What counts as a result: <numbers>.
    Gates: <list>. Report fields: commit, adapter, driver, rustc, wall, exit,
    other-alive-at-start.
    If blocked: say what blocks it and what you tried, do not go quiet.

### Incident note

    WHAT: symptom, first observation time, what was running.
    CAUSE: proven or suspected, with the evidence.
    FIX: commit/revert and the gate that now prevents recurrence.
    COST: minutes lost, lanes affected.

---

## 8. Metrics worth keeping

- Tests verified **per published tip**, not per day.
- Lane success rate: finished with commits / launched. Under 60% means the
  briefs are wrong, not the lanes.
- Time from lane finish to integration.
- Rows refused by the lowerer versus untested - the difference decides whether
  the next batch is authoring or feature work.
- Incidents per hour, and the gate that closed each one.

---

## 9. Scaling rules

- Two agent slots per app instance is a hard cap shared by children and launched
  threads; plan queues around it, do not fight it.
- One device per box. Lanes that need the GPU queue behind the harness lock; lanes
  that only need the compiler use their own target dir and run alongside.
- When the fleet grows, the coordinator's job does not change: publish the tip,
  gate the merge, refill the slots, write down the faults. Everything else scales.


---

## 10. Least privilege - do not leave every model in control of everything

Full admin on every lane is convenient and it is the largest unforced risk in the
whole setup. A firewall protects you from the internet; it does not protect the
repository, the mailbox, the other machines, or the user's profile from an agent
that can write anywhere and run anything. Design the fleet so that a mistake is
contained by the account boundary, not by the model's judgement.

### 10.1 The threat model, stated plainly

An agent with full access can, without meaning to: rewrite history on the branch of
record, delete another station's findings, read SSH keys and browser profiles,
install a service, change firewall rules, run arbitrary binaries, and post as any
station. None of that requires malice - a bad path or a wrong filter is enough. So
the controls are about blast radius, not trust.

### 10.2 Four roles, four accounts, no shared identity

Never one account for everything. On each box:

| role | account | admin | can write | can run | purpose |
|---|---|---|---|---|---|
| provisioner | fleet-admin | yes | whole box | anything | images, installs, ACLs; used only during setup, then disabled |
| station agent | fleet-station | no | its own scratch + channel handoff | builds, tests | runs lanes' work, posts notes |
| lane agent | fleet-lane | no | its own worktree only | compiler + its own test binary | authoring, one deliverable |
| test runner | fleet-test | no | its own target dir + logs | only allowlisted test binaries | owns the GPU, executes queued runs |

The provisioner account is the only administrator, it has no interactive session,
and it is disabled between provisioning runs. An agent never authenticates as it.

### 10.3 Filesystem

- The channel is **read-only** for lanes; only station agents write their own
  findings and handoff files, each into a per-station subfolder.
- The branch-of-record checkout is read-only for everyone except the coordinator,
  which is the only identity allowed to commit to it.
- Each lane is confined to its own worktree plus its own target directory. Deny
  write on the repo root, on sibling worktrees, and on the user's profile.
- Findings and notes live outside the repository, with an explicit ACL - a lane
  that can write to the product tree will eventually commit a report there.

### 10.4 Execution

- Lanes do not get a shell that can run arbitrary binaries. AppLocker or WDAC
  allowlists: cargo, rustc, link.exe, the shell, and the test binary's path. The
  point is not to stop a determined attacker, it is to stop an accidental
  "install this to make the test pass".
- No elevation. UAC stays on, no auto-elevation, no service creation rights, no
  SeLoadDriver, no SeDebugPrivilege.
- PowerShell in ConstrainedLanguage for lane accounts: no Add-Type, no reflection,
  no WMI writes. The station account can have FullLanguage.
- The GPU is owned by fleet-test. Lanes submit runs through a queue rather than
  executing on the device directly, which is also what makes the one-process rule
  structural instead of a promise.

### 10.5 Network

- Lanes have **no egress**. Dependencies come from a vendored directory or an
  internal proxy with a read-only token; if a lane needs something new, it asks
  and the coordinator provisions it. That single rule removes most exfiltration
  and most supply-chain accidents.
- Lanes can reach the channel share read-only and their own handoff folder; they
  cannot reach peer machines at all - no SSH keys, no SMB to the other boxes, no
  WinRM, RDP, or scheduled-task rights.
- Git credentials on lane machines are **read-only** (a deploy key that can fetch
  one repository). There is no push token anywhere in the fleet, which matches the
  policy: handoffs are bundles, not pushes.
- If remote administration is needed, it is the coordinator's account, key-only,
  from one address, and logged - not a shared key on every box.

### 10.6 Secrets

- No secret in environment variables, command lines, or the channel. Windows DPAPI
  or the credential manager, read only by the account that needs it.
- One token per role, scoped to what the role does. Never a shared admin token.
- Agents cannot read or edit their own policy. ACLs, allowlists and scheduler
  definitions are writable by the provisioner only.

### 10.7 What this harness already gives you

- runtime modes per launched thread: launch lanes with workspace-write and
  approvals available, not full-access.
- a file sandbox policy per execution: workspace-write confines writes to the
  workspace; danger-full-access does not. This run used full access for
  convenience - the playbook recommendation is the opposite.
- per-thread launch, so a privileged mode can exist for one provisioning thread
  and never be inherited by the work lanes.

### 10.8 Migration path from "everyone full access"

Do it in this order; each step is reversible and independent:

1. Split accounts (provisioner / station / lane / test) and move the station
   agents onto theirs. Nothing else changes yet.
2. ACL the channel: read-only for lanes, per-station writes.
3. Move device runs to the test-runner queue; lanes submit, runner executes.
4. Cut lane egress and remove any push credentials from every machine.
5. Add the allowlist for lane execution, then ConstrainedLanguage.
6. Automate provisioning (section 11) and disable the provisioner between runs.
7. Turn on drift checking and an audit trail; make a privilege change a logged
   event with a name against it.

### 10.9 The escape hatch (design it, do not improvise it)

Least privilege only works if there is a sanctioned way to get more. Define one:

- a lane that needs a new dependency, a driver, or a host change writes a request
  file with the exact command, why, and what it expects;
- the coordinator reviews it and either provisions it as the station/provisioner
  or declines with a reason;
- the request and the outcome are logged in the channel.

Without that path, agents find their own - and that is how "temporary" full access
becomes permanent.

---

## 11. Automated, unattended environment provisioning

The environment is a build artifact. Treat it like one: versioned, hashed,
reproducible, and installed by a script that is not agent-editable.

### 11.1 Golden image beats in-place setup

Build one image per role (station, lane, runner) and clone it. In-place installs
drift and cannot be diffed. The image contains: OS patch level, pinned GPU driver,
VS Build Tools with the C++ workload and Windows SDK, rustup with the toolchain
from rust-toolchain.toml, a vendored crate directory for offline builds, dxc and
dxil.dll from a pinned release, and the agent runtime. Record every version.

### 11.2 One idempotent script per role

    # provision-station.ps1  (runs as provisioner, once per image build)
    # 1. verify inputs: hashes of every installer and of the vendor dir
    # 2. install VS Build Tools quietly, no restart, C++ workload + SDK
    # 3. rustup: pinned toolchain only; no auto-update
    # 4. unpack the vendored crates; set .cargo/config to offline
    # 5. place dxil.dll and dxc where the test host expects them
    # 6. pin the GPU driver; disable Windows Update driver replacement
    # 7. create fleet-* accounts; apply ACLs and allowlists
    # 8. install the test-runner task (fleet-test) and the sampler task
    # 9. write env-manifest.json (versions + hashes) and a doctor command
    # 10. disable the provisioner account; exit non-zero on any drift

Every step is check-then-act, so re-running repairs instead of duplicating. The
script lives in its own repository the agents cannot write to.

### 11.3 Prove the environment, do not assume it

- A doctor command (read-only, no admin) prints the manifest and compares it to
  the installed state: toolchain, SDK, driver, dxil.dll hash, vendor dir hash.
  Lanes run it first and fail closed on drift.
- The test host itself checks its dependencies (validator present, WARP available,
  device visible) and fails loudly when one is missing - the fault F14 rule.
- A nightly integrity pass on the branch: compile, both-backend filters, full
  suite, bundle verification. Green means green on that image and that commit.

### 11.4 The test-runner pattern (why it is worth the plumbing)

The runner is the only identity that touches the GPU. It watches a queue folder:

    request: { commit, worktree, command (from an allowlist), timeout, env }
    result:  { exit code, wall, adapter, driver, stdout/stderr, other-alive }

It validates the commit exists, the worktree is under the allowed root, the
command is allowlisted, and applies a hard timeout (which also turns a wedged
device into a named failure). Lanes iterate against the queue; the device is never
in an agent's hands, and the one-process rule is enforced by construction instead
of by polling.

### 11.5 What stays human

- Image builds and driver changes.
- Rebooting a box that an agent cannot survive.
- Adding a dependency to the allowlist.
- Anything touching credentials or firewall policy.

Write these down as decision points with a name against each, so a stalled queue
does not sit behind an unnamed question.


---

## 12. Account safety - why the push rule exists

The rule that agents do not push was not caution for its own sake. In this project an
account was suspended by enthusiastic automated activity, and recovery was outside
anything the fleet could do: no appeal path from inside a run, no fallback that is
acceptable, and every station blocked on a human. Assume the same can happen again.

So the default is: **handoffs are bundles, not pushes.** If a project genuinely needs
a remote, give it a narrow, named allowlist instead of credentials plus goodwill.

### 12.1 The allowlist, not the credential, is the control

- One file (or one line in the fleet config) naming the exact repositories this fleet
  may push to. Anything not listed is a refusal, not a judgement call.
- No agent pushes to a repository it was not explicitly given for that task.
- Never use a second account to get around a suspended or restricted one. That is how
  a restriction becomes a ban.

### 12.2 What actually got the account suspended

Automated enthusiasm looks like spam to a platform, and the pattern is usually one of:

- PRs or issues opened across many repositories at once;
- bulk stars, forks, follows, or repeated comments;
- many pushes in a short window to unrelated repositories;
- generated content published without a human looking at it once.

None of these is required to do good work. Test batches belong in bundles; a PR is a
single deliberate act by a named human.

### 12.3 Practical guardrails before any push

1. Check whose credentials are active: gh auth status.
2. Check what is about to go out: git log --stat and git diff against the remote.
3. Check for secrets in the diff: tokens, .env, keys, absolute user paths, hostnames
   you would not publish.
4. Push one repository, one branch, deliberate commits - never a batch of unrelated
   repos.
5. If authentication fails, stop and report. Do not try another account.
6. Never force-push published history. If the artifact to publish is not a descendant of
   the remote head, land only the verified delta as a new commit, or refuse and say why.
   An empty or unrelated repo is not the same as an unpublished one.

### 12.4 Credit and disclosure

Publish who did what (see CREDITS.md in the template): which models, which human
decisions, which faults. A repository that hides its provenance is harder to trust
and harder to hand over.

### 12.5 If it happens anyway

Record it as an incident (section 7 template): what triggered it, which credential,
what the platform said, what was lost. Then write the allowlist rule that prevents
the repeat. The account is the thing you cannot rebuild from a bundle.
