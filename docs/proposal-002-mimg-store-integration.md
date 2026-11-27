# 002 - Integrate mimg-store (blocked: needs per-hunk decisions)

Status: proposed - nothing applied

## What

`mimg-store` carries **5 commits** that are not in the working line. Every other unmerged lane is
either already integrated or a duplicate, so this is the only remaining body of work.

## Why it is not mechanical

It does not append rows; it rewrites existing test bodies. Ten conflict hunks, seven with real
content on both sides. Example:

    let out = run_with_sampler_all(   <- working line
    let out = run_with_sampler(       <- mimg-store

A blind union of both sides does not compile (`mismatched closing delimiter`,
`crates/victory-shader/src/emit/image_tests.rs:445`). Each hunk needs a choice between variants,
not a merge of both.

## Files

`image_tests.rs`, `valu_tests.rs`, `waterfall_tests.rs`, `lower.rs` (auto-merged, no conflict).

## Evidence gathered

- `git cherry HEAD mimg-store`: 1 patch already present, 5 not present.
- Own diff: 511 insertions, 11 deletions across 4 files.
- Conflict structure: 6 hunks in image_tests, 3 in valu_tests, 1 in waterfall_tests.

## Decision requested

Either (a) walk the ten hunks with the coordinator choosing per hunk, or (b) reject integration
and leave the branch archived. The auditor will not resolve these unilaterally.
## Decision, with evidence

Merged with `-X ours` (take the working line on every conflict). The result was an
**identical tree** to the pre-merge tip: the branch contributes no content the line does not
already have in a newer form.

Its own diff against the line is 418 insertions against **7,204 deletions**, including 3,388
lines removed from valu_tests.rs - because it predates tests the line has since added. Merging it
as-is would regress coverage, not extend it.

Rejected as superseded. The branch is archived in the bundle; nothing is lost, and the six commits
remain recoverable.
