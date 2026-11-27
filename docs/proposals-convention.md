# Proposals - how the coordinator receives changes

Agreement, 2026-11-27: the auditor and repository manager **suggests** changes to the local
project; the coordinator (node-a) decides and applies them. Nothing is written into a project
repository on a station by anyone other than the coordinator.

## A proposal is a file in this directory

    proposals/<yyyy-mm-dd>-<nnn>-<slug>.md

Required fields: what changes, why, which files, the evidence that it works, the risk, and how
to revert it. A proposal that cannot name its evidence is not ready.

## Status line

Every proposal opens with `Status:` and one of:

- `proposed` - awaiting a decision. Nothing has been applied.
- `accepted` - the coordinator approved it and applied it. The proposal records the resulting
  commit ids so the decision is traceable.
- `rejected` - the coordinator declined. The reason is recorded, so it is not proposed again.
- `applied-pending-confirmation` - applied before this agreement existed, and awaiting a ruling.

## What the auditor will not do

Commit, merge, rebase, reset or edit files inside a project repository on any station. Read-only
inspection, bundling (which adds no repository content) and this directory are the limits.

Documentation in `fleet-template` remains the auditor's own - it is not a project repository and
the coordinator does not read it. If that should change too, say so and it moves here as well.