# 003 - Recover node-c worker authentication

Status: proposed - nothing applied. This is an outage; needs a go.

## Situation

DESKTOP's worker cannot authenticate to the share (error 86, then 1909). The retry loop holds the
account locked, so it will not recover on its own. The fleet is running on node-b alone and the
coordinator shows no sign of it.

## Proposed sequence

1. Stop scheduled task FleetWorker on DESKTOP. Without this, the retry loop re-locks the account
   within a minute of every fix.
2. Unlock fleet-worker-c on the coordinator and set a new password.
3. Rekey DESKTOP's coordinator.cred on DESKTOP itself (DPAPI LocalMachine), deleting the .bak
   afterwards.
4. Verify with a real net use from DESKTOP, not by inspecting files.
5. Restart FleetWorker and confirm a clean line in worker.log.
6. Re-check node-b's credential the same way - it passes now, but it should be proven rather than
   assumed, since both accounts came through the same rotation.

## Risk

Medium: the fleet is already down on that node; the sequence temporarily stops the task it is
already failing. Queue is empty, so no work is in flight.

## Revert

The old account password is not recoverable (it was generated in memory and never stored). If the
sequence fails, the account stays as it is and the node stays down; no state is lost beyond the
password.

## Also required

Fixing the credential without fixing D2 means the next stale credential does the same thing. See
proposal 004.

## Outcome

- Worker stopped, and the surviving process killed with it (the task reported Running while a
  process was already alive, so a plain start was a no-op).
- fleet-worker-c password reset; DESKTOP rekeyed on the worker; .bak removed.
- Auth verified with a real net use: OK after the 10-minute lockout expired.
- Worker restarted 09:54:48Z; zero loop errors since; exactly one process, lock holding.
- node-b re-verified: auth OK, task Running.

## Root cause, now established

The stored credential was never wrong. **The running worker kept the previous password in memory**
because it reads coordinator.cred once at startup. Rekeying the file did not affect it, so it kept
authenticating with a dead password, retried every ~36s, and locked the account (threshold 10 /
10 min). Any credential rotation must stop the task and kill the process, not just replace the file.
