# Lane brief template

TASK
  One deliverable, stated as a testable outcome. If it cannot be finished in one
  pass, say so before starting.

REPO
  Path, branch of record, published tip <sha>.
  Your worktree: <path> on branch lane/<name>.

INPUT
  Files to read first, and the finding the work implements.

BAR (all of these, or it is not done)
  - compile gate passes
  - the tests you add pass on every backend; if one genuinely cannot run them, the
    skip is counted and an all-skipped run fails
  - one named mutation makes a test go red; restored, tree clean
  - gates: format, lint, policy, your filter, one full run
  - committed, and bundled ref-named from the published tip

ZERO COMMITS
  Not acceptable. Partial batch with named failures, or a patch plus a note
  saying exactly where it broke.

LIMITS
  No push/PR/remote. No runtime captures or dumps. One device process at a time.
  No installing; request it. Stay inside your worktree.

REPORT
  commit | adapter | driver | toolchain | wall | exit | counts |
  other-test-binary-alive-at-start: yes/no
