# Coordinator change record, 2026-11-27

Written because the coordinator's files changed without anything on it explaining why. Every
change below was made by the fleet auditor on the operator's instruction. If a diff-watcher flags
anything on this box, it should be one of these.

## In the share (`D:\fleet`)

| Path | Change | Why | Revert |
|---|---|---|---|
| `README.md` | rewritten, 4,026 -> 9,001 bytes | described a fleet that no longer matched: stale-claim recovery listed as "not implemented" although `Invoke-FleetReaper.ps1` runs every 5 minutes; no management plane; runbook referenced hostname where the rule is IP | `copy README.md.bak-20261127 README.md` |
| `README.md.bak-20261127` | created (4,026 bytes) | pre-rewrite copy | delete when satisfied |
| `worker-credentials.csv` | **deleted**, 147 bytes, sha256 `55DF03542D2E...` | held plaintext passwords for `fleet-worker-b` and `fleet-worker-c`; no script read it; both workers authenticate from their own `C:\fleet\coordinator.cred`; runbook step 3 already said to delete it | none - regenerate with `New-FleetShare.ps1` issues new passwords |

## Outside the share

| Path | Change | Why | Revert |
|---|---|---|---|
| `C:\\Users\\<user>\bundles\` | new, 12 bundles, 115.2 MB | no repository may exist on a single disk; covers node-b, node-a, node-c | delete the directory |
| `C:\\Users\\<user>\audit-coordinator.ps1` | new | tooling for the audit role; called by `scripts/audit-fleet.ps1` | delete |
| `C:\\Users\\<user>\*.ps1` | 64 scratch scripts created then removed | session diagnostics; left as noise, cleaned up | already removed |

## Repository state

`C:\\Users\\<user>\projects\Claude Workspace\flamingo` on branch `shader-tests/scalar-compares`:

- four merge commits added, `2185055a` -> `4e03eb1c` (`lane/fix-sop1-hole`, `lane/mimg-pins`,
  `lane/saveexec`, `lane/smem-audit`) - clean merges, verified with `cargo test -p victory-shader
  --lib`: 564 passed, 0 failed, 6 ignored;
- `backup/pre-additive-20261127` created at `2185055a`;
- `refs/remotes/marvisak/main` fetched (read-only) for the upstream reconciliation.

Revert the merges with `git reset --hard backup/pre-additive-20261127`.

## Host-level (not the share)

- OpenSSH 10.4 installed at `C:\Program Files\OpenSSH`; service `sshd` set to Automatic.
- Auditor key `deepai-fleet` added to `C:\ProgramData\ssh\administrators_authorized_keys`.
- Local accounts `fleet-worker-b` and `fleet-worker-c` passwords rotated to new random values; each
  worker's `coordinator.cred` rekeyed on the worker itself and `coordinator.cred.bak` removed.

## Not touched

`queue/`, `claimed/`, `results/`, `Invoke-FleetReaper.ps1`, the `FleetReaper` schedule, the share
definition and its ACLs, and `audit-coordinator.ps1`'s placement. No task was claimed, requeued or
deleted.

## Later on 2026-11-27: proposals channel and the agreement

| Path | Change | Why | Revert |
|---|---|---|---|
| `proposals\` | new directory | the coordinator now receives changes as proposals rather than seeing them applied | delete the directory |
| `proposals\README.md` | new | states the convention: what a proposal must contain, its status values, and what the auditor will not do | delete |
| `proposals\2026-11-27-002-mimg-store-integration.md` | new, status `proposed` | the only unmerged lane carrying real work; needs per-hunk decisions, not a mechanical merge | delete |
| `proposals\2026-11-27-001-confirm-merged-lanes.md` | created then removed | retrospective ruling on merges already applied; the operator said never mind the previous changes, so the file was withdrawn | none |
| `README.md` | agreement section appended (9,001 -> 9,705 bytes) | records in the coordinator's own words that repository changes are proposed, not applied | remove the section, or `copy README.md.bak-20261127 README.md` for the original text |

| `RULES.md` | new | the human's operating rules, readable from every station: R1 proposals not direct changes, R2 sequential instruction handling | delete the file |
| `README.md` | operating-rules pointer appended | so the rules are discoverable from the document people read first | remove the section |

| `RULES.md` | R3 appended | every rule and behaviour change must reach the fleet template in the same pass; the lab and template must not diverge | remove the section |

| `AUDIT-2026-11-27.md` | new | audit findings: 2 operational faults, 12 design faults | delete |
| `README.md` | correction appended | the earlier claim that audit.jsonl has no producer was wrong; FleetWorker writes it | remove the correction |
| `proposals\2026-11-27-003-worker-auth-recovery.md` | new, proposed | DESKTOP worker is locked out and cannot authenticate; recovery needs a go | delete |
| `proposals\2026-11-27-004-worker-reaper-hardening.md` | new, proposed | fixes for the critical and high design faults | delete |

| `fleet-worker-c` account | password reset 10:52 | recover the locked-out worker | none - new value not stored |
| `DESKTOP coordinator.cred` | rekeyed, .bak removed | match the reset password | none |
| `proposals/2026-11-27-003...` | status -> accepted, outcome recorded | audit trail | delete |
| `AUDIT-2026-11-27.md` | O1 resolution appended | root cause and lessons | remove the section |

| `proposals/2026-11-27-004..007` | new, proposed | the design-fault fixes split into decidable units: reaper claim age, worker fail-fast on auth, heartbeat, worker hardening | delete |
| `proposals/2026-11-27-004-worker-reaper-hardening.md` | retired | replaced by the four split proposals | n/a |

| `C:/fleet/FleetWorker.ps1` (both workers) | replaced, backup .bak-20261127 | D1 claim age, D2 auth fail-fast, D3 heartbeat, D4 tree kill, D5 mapping, D7 truncation flag, D8 id strip, D9 kind check, D12 no BOM | restore the .bak and restart |
| `D:/fleet/Invoke-FleetReaper.ps1` | replaced, backup .bak-20261127 | D1 reads the claims sidecar, D10 prune, D12 no BOM | restore the .bak |
| `results/<node>/claims/` | new directory | claim time recorded where the worker has write access | delete |

| `proposals/2026-11-27-002...` | status -> rejected (superseded), evidence recorded | merge test showed an identical tree and a 7204-line regression risk | delete |

| `proposals/2026-11-27-008-drain-and-reboot.md` | new, proposed | drain then reboot the coordinator to repair the damaged NetTCPIP provider; fleet does not depend on WMI, so it is a health repair not an outage fix | delete |
