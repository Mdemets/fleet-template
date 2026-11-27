# Credits and provenance

This template is the distillation of one 24-hour run. Recording who and what
produced it is part of the method: a fault is only useful if you can trace it back
to a decision.

## Coordinator

| model | role | what it produced here |
|---|---|---|
| deepai/deepseek-v4.1-flash | coordinator (single thread, whole run) | the queue and dispatch loop, every merge and revert, the harness fixes (device mutex, bounded fence waits, vacuous-pass guard), the incident log, this playbook and template |

## Authoring lanes

| model | lanes | what they produced |
|---|---|---|
| deepai/gpt-6-luna | SOP1 batch, DS/LDS pair+offset and contention batches, VOP3 fused/operand-role, VOP1 remainder, SOPK/SOPP scalar gap, harness diagnostics (mandatory validator + DRED), WARP swizzle analysis | the bulk of the new tests, the validator/DRED work, and the evidence that ds_swizzle is a justified hardware-only row |
| deepai/qwen-3.8-flash | encoding-level coverage audit, harness-lifetime read, MIMG store verification, LLVM AMDGPU encoding diff, buffer-format / SOP1-SOP2 / image remainder batches | the coverage table the whole plan was built on, the MUBUF verdict, the null result that our GFX10 tables agree with LLVM, and several test batches |
| deepai/claude-haiku-5-5 | independent verification of the first SOP1 batch | mutations that both went red, and the s_not_b64 low-half hole that the author could not see |

## Peer stations

These ran their own app instances on other machines. Their model identifiers were
not recorded in the channel, so they are credited by station and contribution -
not guessed at.

| station | hardware | contribution |
|---|---|---|
| node-b (10.0.0.11) | RTX 4070 SUPER | the ds_sub WARP-safe lowering fix plus its atomics test, VOPC integer/float/ordered batches, the three-station integration tree, and the device-state crash dataset (4/4 contention, clean after idle) |
| node-c (10.0.0.205) | RTX A5000 Laptop | VOPC integer batch, image rows (r10/r19), VOP3/VOP2/VOP3P batches, and the MIMG harness plan |

## Human

the operator - the machines, the constraints (no pushes, zero-cost models only, no
runtime/title work), the load directives, and the decisions an agent should not
take alone: rebooting a box, choosing repository visibility.

## Note on attribution

Models are not authors in any legal sense; nothing here implies endorsement. This
file exists so the methods and the faults stay traceable, and so a future fleet
knows which lanes to give which kind of work. If you reuse this template, replace
this file with your own provenance record.


## 2026-11-27 - transport, agent and sizing

The second body of work on this template: the fleet stopped being a queue of single workers and became
a measured, parallel, hardware-independent system.

| who | role | what it produced |
|---|---|---|
| the operator | operator and owner | the fleet, the machines and every decision to change them; physical access and credential custody; the domain calls, including stopping work that was heading the wrong way and correcting the record when it was wrong |
| deepai/deepseek-v4.1-flash | agent (this session) | the create-exclusive claim protocol, `FleetAgent.ps1` (one process per station, runspace pool), `assess-fleet.ps1` and the sizing procedure, the efficiency audit, the setup runbook, rules R1-R7 with their evidence, the lessons and thinking protocol, and the measurements behind all of them |

| station | hardware | what it proved |
|---|---|---|
| node-a | i7-11850H, 8c/16t, 96 GB, 1.1 TB share disk, static over Wi-Fi | coordinator on the local path; 16 slots; 12.5x scaling at thread count |
| node-b | i9-14900KF, 24c/32t, 32 GB | the highest scaling measured, 19.5x at thread count; its 9400-odd tasks were where the ACL trap surfaced |
| node-c | i7-11850H, 8c/16t, 96 GB | the silent-worker failure: 16 slots running, zero tasks claimed, zero errors |
| operator workstation (operator workstation) | i7, 6c/12t | the auditor: outside the fleet, read-only, and able to reach every station over SSH |

Three of the four parallelism designs in this work were wrong before they were right. They are recorded
rather than removed, because the reason each failed is the reason the final design holds: a child
process does not inherit its parent's network session, and a claim marker that cannot be created makes
a worker skip every task without saying so.

Measured on the final arrangement: **300 tasks in 8.9 s (33.8 tasks/s), 0 duplicates, 0 failures**, all
three stations contributing.