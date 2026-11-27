# Fleet operating rules

Rules the human has set for how agents work on this fleet. They live here because this share is
readable from every station; a rule that exists only in one workstation's chat log is not a rule.

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
`fleet-template` repository **in the same pass it is adopted** - `AGENTS.md` for the rule as an agent
must read it, `docs/rules.md` for the reasoning and history.

- The lab's `RULES.md` and the template's `AGENTS.md` must not diverge. A rule present in only one
  of them is not adopted, it is proposed.
- The template is what future projects copy. A rule learned here and not written there is learned
  once and lost.
- Amend, do not append-only: when a rule changes, the old text is corrected in both places, and the
  correction is entered in the change record like any other change.
- An agent may draft a rule; only the human adopts one. The same applies to accepted risks.

The auditor is responsible for this propagation as part of the role, not as a favour.

## R4 and R5 - drafted, awaiting adoption

Both come from the 2026-11-27 session and are recorded here as drafts. Under R3 they do not enter
`AGENTS.md` until the human adopts them.

### R4 - Name the recovery path before any restart

Before restarting or rebooting a station, state how it comes back. A headless machine with no
out-of-band access (no IPMI, no console) cannot be recovered remotely if the boot fails, so that reboot
is a physical intervention and the decision belongs to the operator.

Evidence: the coordinator was rebooted to repair a WMI provider and never returned to the network.
Recovery waited for a human. The proposal had named no way back.

### R5 - A bundle is durable only off the machine that made it

Any bundle refresh writes the off-machine copy in the same pass, and the copy's tip is compared against
the source's - not assumed.

Evidence: the bundle holding four lane merges existed only on the coordinator; the off-site copy was
four merges stale when the coordinator went down. Recovery worked only because the lane branches
happened to be inside the older bundle.

## R6 and R7 - adopted 2026-11-27 (thinking protocol P1 and P2)

R6 - Falsify before explaining: name and obtain the disproof before reporting a cause or writing a fix.
R7 - Ask the question that separates two live hypotheses: one discriminating test over confirming runs.

Both are the two practices from docs/thinking-protocol.md that paid for themselves in the session that
produced them. P3-P8 (predict then measure, prior art first, artefacts over descriptions, hypothesis ledger,
timebox a theory without evidence, mark belief versus measurement) remain advisory until adopted.
