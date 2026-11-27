# Incident note template

WHAT
  Symptom, first observed time, what was running at the time.

CAUSE
  Proven or suspected, with the evidence (line numbers, commit, log).

FIX
  Commit or revert, and the gate that now prevents recurrence.

COST
  Minutes lost, lanes affected, work reverted.

KIND
  compile | pipeline/warp | link lock | bundle base | empty branch |
  silent skip | stale thread | transport outage | device state | other
