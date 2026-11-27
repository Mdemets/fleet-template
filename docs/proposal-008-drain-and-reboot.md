# 008 - Drain the fleet, then reboot the coordinator

Status: proposed. Needs a go. Nothing has been stopped or rebooted.

## Why

The coordinator's NetTCPIP WMI provider is damaged: MSFT_NetIPAddress and MSFT_NetTCPConnection
return `Invalid class` (0x80041010), so Get-NetIPAddress and Get-NetTCPConnection are unusable.
Generic WMI works (Win32_OperatingSystem, Win32_Service). Last boot was 2026-11-27 00:11, so the
damage has survived the whole session and every audit has had to route around it.

Honest scoping: **this does not block the fleet.** The queue is file and SMB based; tasks would
flow with WMI entirely dead. What is lost is diagnostic and management tooling on that box -
including parts of the audit that must fall back to netstat and schtasks. So this is a health
repair, not an outage fix, and it can wait for a convenient moment.

## Drain state when this was written (10:32Z)

    queue   0        claimed 0        reaper  10:30:47Z retried=0 done=0 dead=0
    heartbeats: node-c 5s, node-b 7s   (both workers alive, nothing in flight)

A clean window exists now, and the fleet is idle by design at this point in the project.

## Procedure

1. Confirm queue=0 and claimed=0. Do not start until both are zero and stay zero for one reaper
   sweep.
2. Stop `FleetWorker` on both workers (task end plus kill the process - a plain end leaves the
   process running, which is how a stale credential survived earlier today).
3. Reboot the coordinator: `shutdown /r /t 0`.
4. After boot, verify, in this order: `sshd` Automatic and listening; `FleetReaper` task Ready;
   share `fleet` present; `Get-NetIPAddress` responds.
5. If WMI is still broken: `winmgmt /verifyrepository`, then `winmgmt /salvagerepository`, then
   reboot once more. Do not repeat more than once without reporting.
6. Restart `FleetWorker` on both workers; confirm both heartbeats refresh and one pinned smoke
   task per node completes.
7. Resume intake.

## Risk

Low. No work in flight; the code is bundled and mirrored on operator workstation; workers fall back to backoff
on network-path errors rather than treating them as auth failures. Expect two to four minutes
where the share is unreachable.

One caveat: the reboot drops any SSH session to the coordinator, including the auditor's. Access
returns when sshd starts, which is Automatic, so no console access should be needed.

## Revert

None required. A reboot is not a state change beyond restarting services that are already
set to start.
