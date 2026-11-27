# Fleet operating rules

Rules the human has set for how agents work on this fleet. They live here because this share is
readable from every station; a rule that exists only in one workstation's chat log is not a rule.

## How to read these rules

Every rule states its scope in its first sentence and its reasoning in the paragraphs that
follow. The reasoning is part of the rule: it resolves ambiguity and it bounds the scope. A rule
written for stations does not govern fleet services, the agent, or the queue. Applying a rule
outside the scope it names is a misreading, not caution - and caution is no defence, because it
produces the same refusal either way.

The test is one question: what failure was this rule written after, and can that failure happen
here? If it cannot, the rule does not apply.

## R1 - The coordinator owns the project files

Set 2026-11-27. Changes to a local project repository are **suggested** to the coordinator, never
applied directly: no commit, merge, rebase, reset or file edit by an agent other than the
coordinator.

Suggestions go to `proposals/` in this share. A proposal names what changes, why, which files, the
evidence it works, the risk and how to revert. Status is `proposed`, `accepted` or `rejected`; an
accepted proposal records the resulting commit ids.

Still allowed without a proposal: read-only inspection, bundling (which adds no repository
content), records in this share, and documentation outside the project repositories.

## R2 - Instruction updates are handled sequentially

Set 2026-11-27. Prompts from the user - on any workstation, in any session - are processed **in the
order received**. New input does not dismiss a previous request.

What that means in practice:

- Additional input while a request is in progress is **queued behind it**, not treated as a
  replacement for it.
- An earlier request is not abandoned, folded away or silently reinterpreted because a newer
  message arrived.
- Queued requests are not reordered to suit a later message.
- **Only an explicit cancellation** - "nevermind", "drop that", "stop", "forget it" - removes a
  request. Anything else appends.
- If a later instruction contradicts an earlier one, the earlier one is completed or explicitly
  parked first, and the conflict is reported in the response. It is never resolved silently.
- When more than one request is outstanding, each result states what it answers, so the order
  stays visible.

## Why these are written down

Both rules exist because they were broken. R1 followed four merges applied to the working line
without asking. R2 follows sessions where a later message was allowed to absorb an unfinished
earlier one, which loses work quietly and is invisible after the fact.

## R3 - Every rule and behaviour change reaches the template

Set 2026-11-27. Any newly adopted rule, or any change to working behaviour, is added to the
`ai-workfleet-template` repository **in the same pass it is adopted** - `AGENTS.md` for the rule as an agent
must read it, `docs/rules.md` for the reasoning and history.

- The lab's `RULES.md` and the template's `AGENTS.md` must not diverge. A rule present in only one
  of them is not adopted, it is proposed.
- The template is what future projects copy. A rule learned here and not written there is learned
  once and lost.
- Amend, do not append-only: when a rule changes, the old text is corrected in both places, and the
  correction is entered in the change record like any other change.
- An agent may draft a rule; only the human adopts one. The same applies to accepted risks.

The auditor is responsible for this propagation as part of the role, not as a favour.

## R4 and R5 - adopted 2026-11-27

Both came from the same session as R1-R3. R5 was adopted as drafted; R4 was adopted with one
amendment recorded below.

### R4 - A restart needs a named recovery path and the operator's agreement

**Adopted text:** before restarting or rebooting a station, state how it comes back. Without a
recovery path (console, a second admin channel, or someone physically present), ask the operator
before restarting.

**Scope.** Stations only - a machine whose boot may not return, where a failed start costs a
human trip. It does not cover the fleet's own services (dashboard, feeder, reaper), the agent,
or the queue: those have a recovery path by construction - the task starts again locally in a
second - and refusing to restart them converts a trivial repair into an outage.

**Amendment at adoption:** the draft said a restart without out-of-band access "is a physical
intervention, so the decision belongs to the operator" - which reads as a blanket prohibition. The
adopted form permits the restart when the recovery path is named and the operator agrees, because the
restart in question was the correct action. What was missing was the way back, not the permission.

**Evidence:** a restart to repair a WMI provider was proposed without a way back; the station booted
and did not rejoin the network; recovery waited for a human.

### R5 - A bundle is durable only off the machine that made it

**Adopted text:** any bundle refresh writes the off-machine copy in the same pass, and the copy's tip
is compared against the source's, not assumed. Throwaway snapshots are exempt.

**Evidence:** the bundle holding four merges existed only on the coordinator; when it went down the
off-site copy was four merges stale, and recovery worked only because the branch pointers survived
inside the older bundle.

## R6 and R7 - adopted 2026-11-27 (thinking protocol P1 and P2)

R6 - Falsify before explaining: name and obtain the disproof before reporting a cause or writing a fix.
R7 - Ask the question that separates two live hypotheses: one discriminating test over confirming runs.

Both are the two practices from docs/thinking-protocol.md that paid for themselves in the session that
produced them. P3-P8 (predict then measure, prior art first, artefacts over descriptions, hypothesis ledger,
timebox a theory without evidence, mark belief versus measurement) remain advisory until adopted.

## R8 - A STOP file halts fleet automation - adopted 2026-11-27

The operator stops automation by creating a file: STOP beside the script, in C:\fleet, in the worker
directory, or in D:\fleet (the coordinator share). Any state-changing action checks it first and exits
non-zero rather than proceeding. The agent never creates or removes it; only the operator resumes.

Evidence: there was no way to halt a running fleet without editing scripts or killing processes. This is
the cheapest control that works without a UI: one file, checked everywhere that matters.

## R9 - Publication authority

**Rule.** The auditor publishes to the repositories named in `PUSH-POLICY.md` and to no other. The
allowlist decides, not the credential: a token that can reach a repository does not make it
eligible. Everything outside the list is produced as a bundle and left for the human.

**History.** The original policy was local-only because no auditor existed to hold the judgement,
following an incident where an agent pushed another owner's branch into a fork. Amended by the
operator on 2026-11-27 once the auditor was assigned, at which point publishing gained a named
owner and lost a blanket prohibition.
