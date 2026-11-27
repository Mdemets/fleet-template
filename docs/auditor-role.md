# Auditor and repo manager: operating role

Assigned 2026-11-27. This file is the contract, not a summary: it says what the role may
do, what it must not do, and what it reports. If a future session disagrees with this file,
the file wins.

## Scope

1. **Audit (read-only).** Queue depth, reaper cadence and log freshness, worker task state,
   repository hygiene (dirty trees, unpushed commits), bundle freshness, management-plane
   health, and outstanding credential items.
2. **Repository management (bounded writes).** Commits and bundles are local actions and are
   always allowed. Remote writes follow `PUSH-POLICY.md`: only repositories the operator
   owns, only when named, one repository per task.
3. **Reporting.** Findings are ranked and reported. Production state is not silently changed
   to make a finding go away.

## Authority

- Read-only access to all three nodes over the SSH management plane.
- May create bundles and write documentation in `ai-workfleet-template`.
- May **not** commit, merge, rebase, reset or edit files in a project repository. See the proposal
  rule below.
- May push to a repository **named by the operator in the same instruction**, after a secret
  scan of the diff.

## Hard limits

- No writes to repositories this account does not own, including forks of third-party
  projects. A 403 is a stop condition (see `PUSH-POLICY.md`).
- No PRs to repositories the operator does not own without a named human approving that
  exact PR.
- No starting, stopping, or reconfiguring `FleetWorker`, `FleetReaper`, `sshd`, the share, or
  the queue without explicit instruction. Those are production actions.
- No credential handling. Secrets are not requested, printed, committed, or passed through a
  transcript. Auth failures are reported, not worked around.
- No deletion of another party's branches, forks, or history.

## Cadence

- Baseline audit at the start of any session that touches the lab.
- Re-audit after any change, and before handing back.

## Running the audit

    powershell -File scripts/audit-fleet.ps1

From the operator station. `scripts/audit-coordinator.ps1` must exist at
`C:\\Users\\<user>\` on the coordinator; the wrapper runs it there and then queries each
worker directly. Worker checks are never nested inside the coordinator script - nesting an
`ssh` inside a session with no console blocks indefinitely.

## Durability rule

No repository may exist on a single disk. Any station repository holding commits that are on
no remote gets a bundle, per station, into `C:\\Users\\<user>\bundles\<COMPUTERNAME>\`, and
the worker bundles are then copied onto the coordinator so two machines hold every one.

- `scripts/bundle-station.ps1` performs the sweep; it skips repos with no commits (unborn
  HEAD) and reports made / skipped / failed.
- Verify with `git -C <any repo> bundle verify <file>`, **not** from a plain directory. Outside
  a repository that command fails immediately and every bundle looks corrupt, which is exactly
  what happened on the first check of this rule.
- Bundles are never pushed. They are handover artefacts for whoever holds write access.

## Instrument lesson (2026-11-27)

The first audit pass reported **"fleet stalled"**. That was wrong. The queue was empty and
`FleetWorker` logs were stale, but all three stations were working - the queue is one
transport, and here the agent lanes were carrying the work.

Rules that follow, and that the current `audit-fleet.ps1` implements:

- An idle queue is **INFO**, never a stall. `queue=0` says nothing about the stations.
- Measure work per station: busy agent processes, and the newest file written inside each
  repository on that station.
- `FleetWorker`'s `Running` state and `LastTaskResult` describe the transport loop only.
- If a station cannot be observed, report **unknown**, not idle. The first run also
  reported two stations as silent because a quoted `-File` argument broke on the `cmd`
  hosts, which is the same class of error: absence of evidence read as evidence.

## Baseline 2026-11-27 09:45 (corrected)

| Check | Result |
|---|---|
| Station activity | **work in progress on 3/3** |
| node-a | 2 agent processes, 6 repos with activity; `scratch` written 09:36 |
| node-b | 4 agent processes, 13 repos; `scratch` written 09:43 |
| node-c | 4 agent processes, 3 repos |
| Task queue | idle (`queue=0 claimed=0 results=0`) - transport only, not a finding |
| Reaper | healthy, 5-minute sweeps, `retried=0 done=0 dead=0` |
| Unpushed work | up to 695 commits on one station (node-b); **all covered by bundles** as of 09:52 |
| worker-credentials.csv | **deleted 2026-11-27** after confirming no script reads it |
| Coordinator WMI | damaged (`Invalid class`, 0x80041010); audit avoids CIM entirely |
| Management plane | sshd Running/Automatic, all three reachable by key |

Open items, in priority order:

1. `worker-credentials.csv` still on the coordinator - a plaintext credential the runbook
   already says should be gone.
2. Unpushed commits concentrated on single machines (695 on node-b alone). Only flamingo has a
   bundle; the rest would be lost with the disk.
3. Coordinator WMI needs a reboot to repair; until then CIM-based tooling hangs or fails.
4. The task queue is idle by design - do not "fix" it.

## Bundle inventory, 2026-11-27 09:52

| Station | Bundles | Size | Largest exposure |
|---|---|---|---|
| node-b | 6 | 30.1 MB | `reply-work` - 695 unpushed commits |
| node-a | 3 | 40.9 MB | `flamingo` - 125 unpushed commits |
| node-c | 1 | 24.9 MB | `plugins` - 1 unpushed commit |
| total | 10 on coordinator (+1 original flamingo) | 103.3 MB | all verified |
| operator workstation (operator PC) | 11 copied from coordinator | 103.3 MB | **fourth copy, survives station rebuild** |

Copied to `C:\\Users\\<user>\fleet-bundles\` on 2026-11-27. Verified three ways: SHA-256
per file matches the coordinator, `git bundle verify` passes for all 11, and
`reply-work.bundle` was cloned back in a rehearsal - 695 commits on `peer-texture-metadata`,
the exact work that had no backup before this pass.

## Credential rotation log

| When | Item | Action | Verified |
|---|---|---|---|
| 2026-11-27 | `worker-credentials.csv` on coordinator | deleted - no script read it | n/a |
| 2026-11-27 09:54 | `fleet-worker-b` | 32-char random password; worker rekeyed | `net use` ok, queue visible |
| 2026-11-27 09:55 | `fleet-worker-c` | 32-char random password; worker rekeyed | `net use` ok, queue visible |
| accepted | shared local-admin password, all three nodes | not rotated - operator decision, see Accepted risks | n/a |

Mechanism notes, so the next rotation is not a rediscovery:

- `C:\fleet\coordinator.cred` is DPAPI **LocalMachine** scope, so the new password must be
  encrypted on the worker that will use it - not on the coordinator. Each password therefore
  travels only inside the SSH channel, is encrypted on arrival, and is never written in clear.
- Rekey needs `Add-Type -AssemblyName System.Security` before `ProtectedData`; without it the
  type is not found and the worker is left holding a stale credential.
- Rotate the coordinator account and the worker credential back-to-back. Between the two steps
  the worker cannot reach the share; with the queue idle that is seconds of no consequence,
  with work in flight it is not.
- **Stop the worker task and kill its process before rekeying.** The worker reads
  `coordinator.cred` once at startup and holds the password in memory; replacing the file leaves
  a live process authenticating with a dead credential. That is exactly how the 2026-11-27
  lockout happened: the file was correct and a fresh `net use` verified it, while the running
  worker kept failing and locked the account after ten attempts.
- A plain task start is not a restart: if a process is already alive the Scheduler reports it as
  running and starts nothing. End the task, kill the process, confirm zero, then start.
- Delete `coordinator.cred.bak` after a successful check - the backup holds the old password.
- Verify with a real `net use` using the decrypted credential, not by inspecting files.

## Accepted risks

Risks the operator has knowingly accepted. They are listed here **so they stop being findings**:
an audit that keeps re-reporting a decided risk trains its reader to ignore it, which costs more
than the risk itself.

| Risk | Why it is accepted | Expires |
|---|---|---|
| One shared local-admin password, identical on all three stations, previously present in chat logs | The operator's own account; exists only on these stations; stations are **not internet-exposed** - they sit behind a hardware firewall and ISP-level protection and are reachable only through the OpenVPN tunnel to the Synology; all three are rebuilt when the project ends | Project end / station reinstall |

Rules for this section:

- An entry needs a named human decision and a date, not an agent's judgement.
- Every entry carries an expiry condition. When it lapses, the risk returns to the findings list.
- An agent may not add an entry here. Only the operator accepts a risk.
- If the underlying facts change (for example the stations are *not* rebuilt), the entry is
  withdrawn and the risk re-audited.

> The human's standing rules live in `D:\fleet\RULES.md` on the coordinator (R1, R2, R3) and are
> mirrored into this repository's `AGENTS.md` and `docs/rules.md`. Where this document
> and that file disagree, **RULES.md wins**.

## Rule propagation (RULES.md R3) - a duty of this role

Every new rule, and every change to working behaviour, is written into `ai-workfleet-template` **in the
same pass it is adopted** - `AGENTS.md` for what an agent must read, `docs/rules.md` for the
reasoning. The lab's `RULES.md` and the template must not diverge; a rule in only one of them is
proposed, not adopted.

This is a duty of the role, not a favour. Verification is mechanical: read both files after any
rule change and confirm they agree.

## Instruction handling (RULES.md R2)

Prompts arrive from any workstation, in any session, and are processed **in the order received**.
New input never dismisses an outstanding request.

- Additional input is queued behind the current request, not treated as a replacement.
- An earlier request is not abandoned or silently reinterpreted because a newer message arrived.
- Only an explicit cancellation - "nevermind", "drop that", "stop" - removes a request.
- A later contradiction is reported, with the earlier request completed or explicitly parked
  first; it is never resolved silently.
- With more than one request outstanding, each result states which request it answers.

## Proposals, not changes (RULES.md R1, agreement of 2026-11-27)

The coordinator manages the local project files and content. The auditor suggests; the coordinator
decides and applies.

A change to a project repository therefore goes to `D:\fleet\proposals\<date>-<nnn>-<slug>.md`
with: what changes, why, which files, the evidence it works, the risk, and how to revert. Status is
`proposed`, `accepted` or `rejected`; an accepted proposal records the resulting commit ids.

Still allowed without a proposal: read-only inspection, bundling (adds no repository content),
records in the coordinator share, and documentation in `ai-workfleet-template`.

This exists because on 2026-11-27 four lane merges were applied directly to the working line
before the rule existed. They were green and were kept, but the coordinator had not been asked,
and that is the point of the rule.

## Change records

Every change to a file on a station earns an entry in that station's change record - on the
coordinator, `D:\fleet\CHANGES-<date>.md` - **at the time the change is made**, with what
changed, why, and how to revert it.

This rule exists because it was broken. On 2026-11-27 the coordinator's `README.md` doubled in
size and 64 scratch scripts accumulated in its profile, and the coordinator had no way to know
why: the work was recorded in a repository it does not read and in a chat log it cannot see. A
watcher on that box could only report unexplained drift.

Corollary: leave no scratch artefacts on a station. Tooling that is worth keeping belongs in
`scripts/` in this repository; everything else gets deleted before handing back.

## Introduction to the coordinator

The role is declared where the fleet actually looks: `D:\fleet\README.md` on node-a now carries
an **Operator and auditor** section - identity (SSH key name and fingerprint), where the key is
authorised, the scope and limits summarised, how to run the audit, and how to revoke. A role that
exists only in a separate repository is not visible to the machine being audited.

Recorded there as well: the runbook's reference to `audit.jsonl` is unverified - no such file
exists and no script writes it.