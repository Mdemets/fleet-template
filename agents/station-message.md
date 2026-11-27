# Station message template

ITEM <n>
  Commit pin: <sha> (rebased on it, not on an older base)
  What counts as a result: the exact numbers you expect, and which row proves which
  failure mode.

GATES
  List them. A report that says "gates run" without naming them is not a report.

REPORT FIELDS
  commit, adapter, driver, toolchain, wall, exit code, pass/fail/ignored,
  other-test-binary-alive-at-start.

IF BLOCKED
  Say what blocks it and what you tried. Silence is not a status, and "idle"
  without a proposal is a process failure.
