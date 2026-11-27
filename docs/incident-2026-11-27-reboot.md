# Incident: coordinator did not return from reboot, 2026-11-27

## What happened

Per proposal 008, node-a was drained and rebooted to repair a damaged NetTCPIP WMI provider.

- Drain verified before the reboot: `queue=0 claimed=0`, reaper clean, both heartbeats fresh.
- Both `FleetWorker` tasks hard-stopped (task end plus process kill); workers left `Ready` with
  zero processes.
- Reboot issued ~10:40Z.
- **The coordinator did not return.** Not at 10.0.0.10, not at any other address on the
  subnet, and not present in the router's DHCP client list - so it never brought a network
  interface up.

## What was ruled out

| Hypothesis | Evidence |
|---|---|
| VPN down | node-b .118, DESKTOP .205 and LAN gateway .1 all answer; tunnel adapter Up at 172.16.0.6 |
| DHCP moved it | full /24 scan for SSH found .118, .203, .205 only; router lists no node-a |
| sshd failed to start | no ping either, and no DHCP lease - it is below the OS service layer |
| Slow boot/update | still absent after ~12 minutes of polling |

## Impact

- The fleet queue and share are on that box, so the transport is unavailable.
- No work was lost: nothing was in flight, the drain was verified, and workers are stopped so
  nothing is retrying or locking accounts.
- **Code is not at risk.** The full bundle set (11 bundles, 103 MB) is on operator workstation, outside the
  lab. Repositories on node-b and DESKTOP are intact and independent of the coordinator.

## Root gap - the real failure

The proposal assumed sshd would come back on its own: it is Automatic, so a normal reboot
returns remote access. That assumption holds only if the machine boots. There is **no
out-of-band path** - no IPMI, no KVM, no console - so a boot that stops before the network has no
remote recovery, and the proposal named no way back if the box stayed down.

A headless reboot needs one of: a verified out-of-band path, physical presence, or an accepted
risk that the box may not return. That decision belongs to the operator, not to the auditor.

## Recovery when it is back

1. Confirm the share `fleet` is present and `D:/fleet` intact.
2. Verify `sshd` Automatic and listening; `FleetReaper` Ready.
3. Check the WMI repair: `Get-NetIPAddress` responds.
4. Start `FleetWorker` on both workers; confirm both heartbeats refresh.
5. One pinned smoke task per node.
6. If WMI is still broken: `winmgmt /verifyrepository`, then `/salvagerepository`, then at most
   one more reboot - and only with an out-of-band path this time.

## Proposed rule (needs human adoption)

R4: before any restart or reboot of a station, name the recovery path. A reboot of a headless
machine without out-of-band access is a physical intervention, and requires either a human on
site or an explicit acceptance that the machine may not return.

## Follow-up: restoring the code line without the coordinator (11:05Z)

The flamingo line lived only on the dead host. Restored on node-b from the off-site bundle:

    clone  flamingo-20261127-0859.bundle   -> 2185055, 1341 commits, 41 lane branches
    replay lane/fix-sop1-hole, lane/mimg-pins, lane/saveexec, lane/smem-audit  -> 4/4 clean
    result 0dae230, 1349 commits, tree 7a216c2d, fsck clean, tree clean

The commit count reconciles: 1341 + 4 lane commits + 4 merge commits. The original merges had no
content decisions, so replaying them reproduces the same tree.

### The gap this exposed

The postmerge bundle - the one that actually contained the four merges - was written **only to the
coordinator**, at `C:/Users/the operator/bundles/node-a/`. The off-site copy on operator workstation was the 0859
snapshot, four merges stale.

So the fleet's durability rule was satisfied on paper and defeated in practice: the newest bundle
sat on the same disk that became unavailable. Recovery worked only because the four lane branches
were themselves inside the older bundle, so the merges could be replayed. Had any merge involved a
hand resolution, that work would have been lost.

### Proposed rule (needs human adoption)

R5: a bundle is only durable when it exists off the machine that produced it. Any refresh must
write the off-site copy in the same pass, and the off-site copy's tip must be checked against the
source's tip - not assumed.