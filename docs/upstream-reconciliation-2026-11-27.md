# Upstream reconciliation, 2026-11-27

Two upstream lines are mirrored locally and worked simultaneously, by design. This file records
where each mirror actually sits, because the fleet's notes cite commits that no checkout holds.

## Upstream references (read from GitHub, 2026-11-27 10:0x)

| Line | Repository | main | Tip date |
|---|---|---|---|
| A | `Marvisak/VIctory` (authoritative) | `63bcca4` | 11-26 00:27 |
| B | `JMAN730/project-flamingo` (fork of A) | `ee0c171` | 11-26 14:59 |

`JMAN730/victory` **redirects** to `JMAN730/project-flamingo` - it is not a separate repository,
so any checkout whose origin is `JMAN730/victory` is a line-B clone under an old name.

## Naming history: why the directory names cannot be trusted

Both upstreams were called **`VIctory`** when the fleet mirrored them: `Marvisak/VIctory`
(authoritative) and JMAN730's fork, which bore the same name. JMAN730's was later renamed to
`project-flamingo`, so `JMAN730/victory` now **redirects** there - `gh api repos/JMAN730/victory`
resolves to `JMAN730/project-flamingo`.

Consequences that caused real confusion in this audit:

- A local directory called `victory` or `VIctory` does **not** identify which line it tracks.
  Only the resolved remote URL does, and for line B that URL may be the *old* name that still
  redirects.
- GitHub repository names are case-insensitive: `marvisak/victory` and `Marvisak/VIctory` are
  one repository, not two.
- Two clones with the same name can be hundreds of commits apart, on different lineages.

Before comparing any two checkouts, resolve `origin` first. The name is not evidence.

## Local checkouts

| Station | Directory | Line | Tip | Relation to that line's main |
|---|---|---|---|---|
| node-a | `flamingo` | B | `2185055` | 147 ahead, 217 behind |
| node-a | `victory` | B (old name) | `820bc3b` | stale, 11-24 |
| node-b | `victory` | A | `2daea570` | **not an ancestor of main** |
| node-b | `VIctory` | A | `ffe310e` | 479 behind - the fork base |
| node-c | `victory` | B (old name) | `2daea570` | stale, 11-25 |
| node-c | `victory` #2 | A | `da82e44` | 79 behind - freshest A mirror |

## Findings

1. **No checkout sits at `63bcca4`.** The freshest line-A mirror is 79 commits behind it; the
   fork base is 479 behind. `node-c-upstream-issues-20261127.md` states its measurements were
   taken "at 63bcca4", but that commit was absent from every station until it was fetched for
   this audit. The claim is therefore not reproducible from the box that made it - either the
   measurements were taken in a checkout that no longer exists, or the base was cited rather
   than used.
2. **Neither line is in sync.** Line B is 147 ahead and 217 behind its own remote; line A's
   mirrors are 79 and 479 behind. Integration has not happened recently in either direction.
3. **`2daea570` is on a divergent lineage.** Two clones tracking the same upstream report very
   different history depths (1136 vs 613 commits), and the older one is not an ancestor of
   current main - consistent with an upstream rewrite or a force-push. Any work based on it
   needs rebasing, not merging.
4. **The findings repository has 28 uncommitted paths** on node-b, including the whole
   `node-c/` directory. Today's evidence exists as loose files on one disk.

## Decision required

Which line is the integration target?

- **A wins** (authoritative upstream): the fleet's 1,128 commits must land on a base 479 commits
  newer, and every finding "verified" on the old base must be re-run.
- **B wins**: line A's 479 commits must be pulled into the fleet line first, and A's own mirrors
  refreshed to `63bcca4`.

Until this is decided, treat measurements as valid only for the exact tip they were taken on -
and record that tip with the measurement.

## How to re-check

    git -C <clone> fetch https://github.com/Marvisak/VIctory.git main:refs/remotes/marvisak/main
    git -C <clone> fetch origin
    git -C <clone> rev-list --count HEAD..refs/remotes/marvisak/main   # behind A
    git -C <clone> rev-list --count refs/remotes/marvisak/main..HEAD   # ahead of A

Run it per checkout, not per station: the stations hold different tips of the same repository.