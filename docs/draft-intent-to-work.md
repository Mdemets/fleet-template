# Draft: intent to work, without manufacturing motion

Status: **draft**, 2026-11-28. Not yet implemented end to end; the fleet currently implements stages 4-5 (and
half of 1) only. Written after a night that produced 38,000 tasks and 22 useful answers, then 52 shards
and a clean distribution - the difference between those two runs is the whole point of this document.

## The chain

| # | stage | who | output | gate |
|---|---|---|---|---|
| 1 | intent | operator | a prompt, in their words | - |
| 2 | interpretation | coordinator | goal + **acceptance criteria**, restated | **G1: operator confirms** |
| 3 | decomposition | coordinator | *checks*, not steps (see schema) | each check must have a script verdict |
| 4 | normalisation | coordinator | task documents in the queue | evidence embedded, no run-time fetch |
| 5 | execution | workers | results with evidence | backpressure, per-resource locks |
| 6 | judgement | coordinator | verdict table -> next checks or **stop** | **G2: anything outward** |

Stage 3 is where tonight's failures were born twice: once as "keep the fleet busy" (no verdict, so any
output counts), once as whole-crate test runs (units too large to spread). A *check* is small, answerable
by one command, and has a verdict that is not an opinion.

## Unit schema (draft)

```json
{
  "id": "shard-victory-gpu-pipeline",
  "question": "do the pipeline tests pass at this commit?",
  "evidence": {
    "base": "ee0c171",
    "inputs": ["worktree C:/Temp/v-ee0c171"],
    "assumed_env": { "RUSTUP_HOME": "C:/Users/Maarten/.rustup" }
  },
  "command": "cargo test --release -p victory-gpu pipeline",
  "done_when": { "kind": "exit", "equals": 0 },
  "resource": "cargo-build",
  "timeoutSeconds": 2400,
  "requeue_if_blocked_after": 15
}
```

Four fields carry the weight: `done_when` makes the verdict machine-checkable; `evidence` removes the
network from the execution path; `resource` makes contention visible instead of random;
`requeue_if_blocked_after` stops a blocked unit from occupying a slot.

## Backpressure

A unit that cannot start within `requeue_if_blocked_after` seconds **puts itself back in the queue and
exits**. Tonight 49 units were claimed at once and 46 sat in a lock-wait loop, so the board showed 49
busy slots and the fleet advanced at roughly one unit per station. The rule: queue holds work, slots
hold work in progress, and the two are never confused.

Per-resource serialisation is still needed (one cargo build per station), but a waiter is not a worker.

## Stop condition

The chain as usually drawn can always produce more work. Declared explicitly:

> **Stop when no unit can be generated from the declared scope.** Supply remaining = 0 and queue = 0.

The board already computes this (`status/supply.json`), and `FleetWatch` shows `ENDGAME` when it is true.
Re-verification cycles are a deliberate, timed decision - never the default - or the fleet refills itself
forever to look busy.

## The two gates

- **G1, interpretation.** Before any decomposition: restate the goal and the acceptance criteria, and have
  the operator correct them. Cheap, and it is the only point where a wrong understanding is still cheap.
- **G2, consequence.** Before anything leaves the machines - a PR, a comment on another's tracker, a
  reboot. The Leonida exclusion and the push policy live here. G1 does not cover this: an operator can
  confirm the right goal and still not want it published.

## Failure taxonomy (each shapes a unit)

| failure | example from tonight | what the unit must carry |
|---|---|---|
| environmental | SYSTEM rustup home tried to install a toolchain | `assumed_env`, asserted at start |
| contention | `link.exe` 1104 from two shards sharing a target dir | `resource`, serialised, with requeue |
| quota | 60 req/h anonymous GitHub, 99.9% fetch failures | evidence embedded, no run-time fetch |
| absent | no Radeon in the fleet for an AMD-only task | a `finding`, not a claim |

## Metrics that keep it honest

- **useful / executed** - the only ratio that separates a working fleet from a busy one.
- **ETA** = remaining units / measured completion rate, not queue depth.
- **endgame flag** - true only when supply is genuinely exhausted.

## What is missing before this is real

1. Stage 2 and 3 need a reasoning lane on the coordinator; today that is a human in this thread.
2. `done_when` needs a small evaluator so a worker can assert its own verdict rather than print text.
3. The requeue path needs the worker to rewrite its own task document - today tasks cannot enqueue.

None of these is large; all three are what separates the diagram from the system.
