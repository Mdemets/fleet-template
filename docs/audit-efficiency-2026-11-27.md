# Fleet efficiency audit, 2026-11-27

Measured by `scripts/audit-efficiency.ps1` against the live coordinator share. Everything below comes
from artefacts on disk; nothing is estimated.

## Numbers

| Metric | Value |
|---|---|
| tasks recorded | 2 |
| succeeded (exit 0) | 0 (both rejected: `unsupported kind 'smoke'`) |
| execution time min / median / max | 0.053 / 0.110 / 0.110 s |
| total task seconds | 0.163 s |
| measured window | 12.4 min |
| worker capacity | 2 workers x 12.4 min = 24.9 worker-minutes |
| utilisation | **0.011 %** |
| reaper sweeps logged | 312 |
| retried / done / dead / pruned | 4 / 3 / 0 / 0 |
| sweep cadence | 293.4 s (5 min, as designed) |

## What these numbers mean, and what they do not

**Utilisation 0.011 % is not an efficiency score.** It says the fleet had no work to do. Utilisation
measures demand against capacity; with an empty queue it reports the absence of demand, not a failing
machine. Reporting it as "the fleet is 0.011 % efficient" would be the false-precision trap this audit
exists to avoid.

**Success rate 0 % is my fault, not the fleet's.** Both tasks used `kind = 'smoke'`, which the worker
rejects at execution time (`exitCode = -2`). The transport did its job perfectly: both tasks were
claimed within a poll cycle, executed, and produced a well-formed result record with the error.

**Transport efficiency is the metric that is actually computable, and it is healthy:**

| Signal | Reading |
|---|---|
| claims that produced a result | 2 of 2 (100 %) |
| dead letters | 0 |
| retries across 312 sweeps | 4 (1.3 %) |
| sweep cadence | 293.4 s, equal to the 300 s design |
| stale heartbeat | none while both workers ran |

## What cannot be measured, and why

| Gap | Cause | Fix |
|---|---|---|
| queue wait (submit -> claim) | no `submittedAt`; the queue file is deleted on claim | write `submittedAt` into the claim sidecar |
| worker idle vs busy | heartbeat carries only `{node, ts}` | add `state`, `currentTask`, `queueDepth` |
| retry cost | reaper counts retries, not the duplicated work | record the retried task's wall time |
| real task latency | n=2, both trivial and both invalid | needs genuine workload |

## Design fault found while measuring

The worker rejects an unknown `kind` **after** claiming the task. That burns a claim, writes a failure
result, and needs the reaper to clear it. Validation belongs at enqueue: a task that cannot run should
never enter the queue.

## Honest summary

Fleet transport: healthy (100 % claim-to-result, 0 dead letters, cadence on target).
Fleet throughput: unmeasurable today - there has been no workload beyond two synthetic tasks that I
malformed. The fleet is idle, not inefficient, and it cannot be shown to be efficient until it is given
work that reflects what it is for.