# Fleet: pull-based three-node lab

Coordinator: **node-a** (`10.0.0.10`).
Workers: **node-b** (`10.0.0.11`), **node-c** (`10.0.0.205`).

All three live on `10.0.0.0/24`, reached from outside over the OpenVPN tunnel
(`172.16.0.6` -> Synology -> LAN, ~20-45 ms). **Addresses are DHCP**; the queue addresses
the coordinator by IP, so a lease change breaks the share path. Pin reservations.

## Why this shape

Nothing reaches into a worker *to move work*. Workers poll the coordinator's share,
claim one task, run it, and write a result. A compromised worker can read the queue and
write its own folders - nothing else. No admin share is required, and no worker credential
is stored on the coordinator.

Workers claim by moving `queue/task-<id>.json` into `claimed/<node>/`. The move needs delete
on `queue` but not write, so a worker cannot inject work for another node.

### Deviation: the management plane

Since 2026-11-27 the nodes also carry an SSH management plane (next section). That is a
deliberate exception to the original rule "no inbound listening surface on workers" - it
was added so an operator can diagnose and drive the lab remotely without RDP. It is not
part of the task protocol, tasks flow with or without it, and it can be removed without
touching the queue.

## Share layout (on node-a, D:/fleet, published as \\10.0.0.10\fleet)

    queue/                  shared pool: anyone claims from here
    queue/<node>/           pinned queue: only that node may claim
    claimed/<node>/         each worker writes only its own folder
    claimed/<node>/done/    reaper moved a finished claim here
    claimed/<node>/dead/    reaper gave up after MaxAttempts
    results/<node>/         each worker writes only its own folder; coordinator reads all

Use the IP, not the hostname: the workers do not resolve node-a through DNS, and
provisioning writes the IP into `coordinator.unc` for that reason.

## Load distribution

The worker claims by moving a task file, and processes **one task per sweep from the shared
pool** before sleeping a jittered 10-20s. Without that limit a single worker drains the whole
shared pool in one pass, so distribution is bimodal rather than fair.

Pinned queues drain fully, because no other node can claim from them. Pin work that belongs
on a specific machine; leave everything else in the shared pool.

## Reaper (stale-claim recovery)

`D:/fleet/Invoke-FleetReaper.ps1`, registered as scheduled task **FleetReaper**, running as
SYSTEM every 5 minutes (`-Install` registers it).

    lease = task.timeoutSeconds (default 600s)
    a claim older than lease + 300s grace is stale
    result present      -> moved to claimed/<node>/done/
    no result, attempts < 3 -> requeued with attempts+1
    no result, attempts = 3 -> moved to claimed/<node>/dead/

Every sweep appends one line to `D:/fleet/reaper.log`.

## Management plane (SSH)

| From | To | Path |
|------|----|------|
| operator PC | node-a | `ssh node-a` |
| operator PC | node-b | `ssh node-b` |
| operator PC | node-c | `ssh node-c` |
| node-a | node-b, node-c | coordinator pushes to workers |

- OpenSSH for Windows **10.4** on all three: `C:\Program Files\OpenSSH`, service `sshd`,
  `AUTO_START`. Workers also keep the inbox copy in `System32\OpenSSH`; the service points
  at `Program Files`.
- Administrator logins authorise from `C:\ProgramData\ssh\administrators_authorized_keys`
  (SYSTEM + Administrators only).
- Operator key: `deepai-fleet`, fingerprint `SHA256:2TYAMZd7Ig0vFCBx0+vbdY1ZJobsQ8lHiZt7cuDSTLQ`.
- node-a holds its own `id_ed25519` for reaching the workers.
- Default shells differ: **cmd** on node-a, **PowerShell** on node-b and node-c.
  Wrap explicitly (`powershell -NoProfile -Command "..."`) rather than assuming.

## Runbook

0. Rotate the shared local-admin password on all three machines. It has been in chat logs.
   ACCEPTED RISK - not a finding (operator decision 2026-11-27): this is the
   operator's own account, it exists only on these three stations, and all three
   are scheduled for a clean rebuild when this project ends. The stations are not
   internet-exposed: hardware firewall at the perimeter plus ISP-level protection,
   reachable only through the OpenVPN tunnel to the Synology. Do not re-raise it.
   (Worker share accounts are separate and were rotated 2026-11-27 09:54-09:55;
    see the rotation log in fleet-template docs/auditor-role.md.)
1. On node-a, as administrator:
       ./New-FleetShare.ps1 -Workers node-b,node-c
   Writes D:/fleet/worker-credentials.csv with one unique password per worker account.
2. For each worker, once, as administrator on that machine:
       $u = 'fleet-worker-b'
       $p = Read-Host -AsSecureString 'coordinator password'
       ./New-FleetWorker.ps1 -NodeName node-b -CoordinatorUser $u -CoordinatorPassword $p
   Creates the standard user, stores the coordinator secret, registers the FleetWorker task.
3. Delete D:/fleet/worker-credentials.csv on the coordinator.
   Deleted 2026-11-27 after confirming no script reads it and both workers authenticate from their own coordinator.cred.
4. Enqueue a smoke task on the coordinator:
       $t = @{ id = 'smoke-1'; kind = 'powershell'; payload = @{ script = 'Write-Output hi' }; timeoutSeconds = 60 }
       $t | ConvertTo-Json -Depth 5 | Set-Content 'D:/fleet/queue/task-smoke-1.json'
   Expect results/<node>/result-smoke-1.json within ~30 seconds and a line in audit.jsonl.
5. Verify the boundary: from a worker, try to write directly into queue/. It must fail.
       'x' | Set-Content '\\10.0.0.10\fleet\queue\injected.json'   # access denied
6. Revoke test, on the coordinator:
       ./Revoke-FleetWorker.ps1 -Node node-c
   The other node must keep working.

## Task file

    { "id": "smoke-1", "kind": "powershell",
      "payload": { "script": "..." }, "timeoutSeconds": 600 }

## Result file

    { "id": "smoke-1", "node": "node-b", "kind": "powershell",
      "claimedAt": "...", "finishedAt": "...", "exitCode": 0,
      "timedOut": false, "stdout": "...", "stderr": "", "error": null }

## Known limits, deliberately

- Workers cannot read each other's results. The coordinator can read all.
- Stale claims are handled by the reaper (lease + grace, 3 attempts), not by hand.
- fleet-worker is a standard user. If a task needs elevation, do not raise the account -
  model it as a separate, human-approved job.
- DPAPI is LocalMachine scope because the scheduled task runs as a different user than the
  installer. The file is protected by its ACL, not by the DPAPI scope.
- The management plane shares one operator key and one local `the operator` admin account across
  all three nodes: a single key theft reaches the whole lab. Rotate or per-node-scope before
  treating any node as a trust boundary.
- DHCP addressing (see top).
- node-a's WMI provider is damaged (`Get-Net*` / CIM return `Invalid class`, 0x80041010).
  The queue is file/SMB based and unaffected; CIM-based tooling on that node is not, until it
  is rebooted (`winmgmt /verifyrepository`, then `/salvagerepository`).


## Operator and auditor

Introduced to this record on 2026-11-27. The fleet is operated by **the operator** (human); an AI
auditor and repository manager acts on his instruction and holds the SSH key named below.

- **Identity.** SSH key `deepai-fleet`, ED25519, fingerprint
  `SHA256:2TYAMZd7Ig0vFCBx0+vbdY1ZJobsQ8lHiZt7cuDSTLQ`, presented from the operator station
  (operator workstation) over the OpenVPN tunnel.
- **Where it is authorised.** `C:\ProgramData\ssh\administrators_authorized_keys` on all three
  nodes, alongside node-c's own key.
- **Scope and limits.** The contract is `fleet-template` -> `docs/auditor-role.md`. In short:
  read-only audit across the nodes; local commits and bundles; documentation in that repository;
  **no** pushes to repositories the operator does not own; **no** production actions - worker
  restart, share or queue changes, credential rotation, service changes - without an explicit
  instruction.
- **How to audit.** `scripts/audit-fleet.ps1` from the operator station. It reports per-station
  activity, queue state, repository hygiene and outstanding items. An idle queue is reported as
  INFO: it is a transport, not a measure of work.
- **Revocation.** Delete the `deepai-fleet` line from `administrators_authorized_keys` on all
  three nodes; stop `sshd` if the management plane is no longer wanted. Nothing in the task
  protocol depends on either.

### Unverified claim in this document

Step 4 of the runbook says a smoke task should leave "a line in `audit.jsonl`". **No such file
exists on the coordinator and no script writes it.** Either the producer was never written or it
was removed; until one exists, treat that half of the step as unverified rather than as passing.

## Agreement: proposals, not direct changes (2026-11-27)

The auditor and repository manager does **not** write into a project repository on any station -
no commit, merge, rebase, reset or file edit. Changes are proposed in `D:\fleet\proposals\`; the
coordinator decides and applies them.

Allowed without a proposal: read-only inspection, bundling (adds no repository content), this
share's own records, and documentation in `fleet-template`.

A proposal names what changes, why, which files, the evidence that it works, the risk and how to
revert. Status is `proposed`, `accepted` or `rejected`, and an accepted proposal records the
resulting commit ids so the decision stays traceable.

## Operating rules

The rules the human has set for how agents work here are kept in `RULES.md` in this share, so
they are readable from every station. Two so far: the coordinator owns the project files
(changes are proposed, not applied), and instruction updates are handled sequentially - new input
queues behind an outstanding request rather than dismissing it.

### Correction: the audit log does exist

An earlier revision of this file said audit.jsonl had no producer. That was wrong: FleetWorker.ps1
appends to results/<node>/audit.jsonl on every finished task. The file is absent only because no
task has finished since results was cleared.
