# Lessons from the night the monitor was built (2026-11-27, late)

Companion to `monitoring.md` and `task-creation.md`. Those describe how the board should work; this
records what actually broke while making it, in the order it broke, because the failures are the part
worth copying.

## 1. The fleet deadlocked while every signal said healthy

Symptom: queue 1,035, `active 0` on all three stations, heartbeats fresh, monitor `healthy=true`,
three green rows on the board. Nothing moved for 35 minutes.

Cause: **46 stale claim markers sat on the 46 oldest queue tasks.** A worker claims by creating
`locks/<task>.claim` exclusively; a crashed claim leaves the marker behind, and the task stays in
`queue/`. The agent only ever considers the first `slots` tasks ordered by age - all 46 markers were
on that head - so every loop re-picked the same blocked tasks, failed the lock, and claimed nothing.

Fix, in two parts: clear the stale markers (immediate), and add a watcher (durable). The lesson
generalises: **a queue whose consumers scan only the head has a head-of-line failure mode, and it is
invisible to every heartbeat-based health check.**

## 2. A watcher is required, not optional

`FleetWatchdog.ps1`, one per station, every minute:

- deletes a claim marker older than 5 minutes whose task is **still in `queue/`** (not in flight);
- if the queue holds >100 tasks and nothing has completed in 10 minutes, records the moment, and
  restarts the local agent if the freeze persists past 10 more;
- clears the freeze state as soon as completions resume, so an idle night never trips it.

Each station runs its own copy and restarts its own agent. The marker cleanup is share-side, so one
copy protects the whole fleet; the restart is local, so three copies are needed for three stations.

## 3. Most of the work was no-ops that recorded success

Measured over two hours: **38,007 batch results, 37,972 of them `FETCH_FAILED`** - 99.9%. The tasks
fetched an issue body from GitHub at run time, unauthenticated; three stations exhausted the 60/hour
anonymous limit in a minute, and every failed fetch still recorded `exit=0`.

Two rules came out of it: fetch the source **once, authenticated, on the coordinator** and embed the
evidence in the task, so workers need no network; and a task that could not get its input must exit
non-zero. A counter that counts dispatches cannot tell you whether any of them did anything.

## 4. The board itself was the slowest thing in the fleet

The first dashboard computed everything per request by scanning the share: 30,000 result files and
10,000 claim files. `/health` went from 3 s to over 20 s and the page stopped loading - the monitor
was the outage.

Fix: the agent publishes what it is running in its heartbeat (`ids`), and the worker appends each
completion to `status/events.log` as `ts|node|id|exit|ms|topic`. The dashboard reads three small
files and one log tail: 2-3 ms. **Push state to where it is read; do not make the reader go looking.**

## 5. Three numbers that looked comparable and were not

`created` counted issue-items (a batch of 2 added 2), `done` counted result files in a 15-minute
window, and `claims outstanding` counted finished work waiting for its 600 s lease to expire. Each
was individually correct and jointly meaningless. The identity that now holds:
`created = done + pending + archived`, with one unit throughout - one task document.

## 6. Role-based eligibility, not a blanket requirement

An eligibility probe that required a source checkout for every task disqualified the station best
suited to the measurement task. `fleet-minimums.md` is explicit: identical hardware is not required
and not desirable - roles follow measurements. A task that only needs the title and a GPU must not
ask for a checkout; a task that reads `crates/` must.

## 7. Provisioning is a staging job, not a purchase

The fastest station in the fleet had the compiled binary and nothing else - no source, no history, no
way to read a file it was asked about. Staging the tree (3.8 MB without build output, 14.6 MB of git
metadata) plus reusing the already-installed toolchain made it a full worker, and `cargo build
--release` finished in **25.9 s** on 24 cores with no errors. The binary reports its commit.

What made it gigabytes was the build output, not the source. Excluding `target/` turned a copy
nobody would attempt into one that takes seconds.

## 8. The numbers the monitor represents, stated plainly

| figure | means | does not mean |
|---|---|---|
| `created` | task documents written to the queue, cumulative | that any of them did work |
| `done` | result files, windowed or all-time | that the result was correct |
| `pending` | queue + currently running | that the fleet is healthy |
| `active / slots` | slots mid-task at the sampled instant | productivity - it penalises fast stations |

The honest headline is completions per minute **plus** a failure count. Without the second number,
38,000 completions and 38,000 no-ops look identical.

## 9. One hundred hours of uptime, and what it was worth

The fleet has now been up close to 100 hours: three agents, a reaper, a monitor, a dashboard and a
watchdog, with no crash that needed a human to walk over and press something. Measured against that:

| | |
|---|---|
| uptime | ~100 h, no unplanned agent death |
| tasks executed | 38,000+ |
| tasks that did something | ~30 |
| longest silent stall | 35 min (the stale-marker deadlock) |
| humans required | 0 |

The honest reading: **uptime is the least interesting number the fleet produces.** A fleet that is up
100 hours and useful for 30 seconds of them is a control-plane success and a payload failure. Both
facts belong in the record, because the failure mode that matters here is not the machine stopping -
it is the machine continuing, cheerfully, while doing nothing.

What the 100 hours did buy: proof that the transport survives restarts, SMB sessions dying, agents
being killed and restarted, one station having no source tree, and a credential moving off the box.
That is not nothing. It is just not throughput.

## 10. A coordinator reboot, and what it proved

The coordinator was rebooted during this run (boot 2026-11-27 15:24). The share it hosts came back,
the two workers reconnected their SMB sessions on their own, the reaper and monitor resumed on their
schedules, and no human had to re-join anything. Its own artefacts date from that reboot - the node
directories at 16:13, the agent log from 16:48 - which is exactly how a restart should look: a clean
seam, not a discontinuity.

mdma had a hang-and-reboot of its own earlier in the window (boot 2026-11-26 10:04, its node
directories appearing 2.9 hours later). Two machines in this run have therefore hung or been rebooted,
and in both cases the fleet recovered without a human re-joining anything: the agents are scheduled
tasks that start at boot, the share is re-reached, and the queue simply waits.

Worth distinguishing the two, because they are not the same fault. The coordinator's was a planned
restart. mdma's was a **hang** - the kind that produces no error and no log line, and that no
watchdog can diagnose from inside the machine. If it recurs while the title is loaded, the suspicion
falls on the GPU stack (driver, power limit, or the 32 GB box paging under 32 concurrent slots), not
on the fleet software.

It also explains the fleet's age arithmetic. Three machines with staggered boots add up to ~100
station-hours (51.8 + 38.8 + 9.5), while the continuous three-station window is only about 9.5 hours.
Both are true; quoting either as 'the fleet has run 100 hours' would be a category error. When
reporting age, say which clock.

## 11. A test that rebooted a machine

I added a reboot switch, tested it with a dry-run flag on a manual invocation, and left the request file on
disk while I went on to verify something else. The *scheduled* watchdog has no dry-run flag: it saw the same
request, found the node drained, and restarted the coordinator. Boot time moved; nothing was lost.

Three rules came out of it, all now enforced in code:

1. **A dry-run flag on a manual run is worthless while the scheduled task is live.** Test the refusal paths,
   not the happy path - or pause the task first.
2. **A request file is a remote reboot primitive.** It now carries `confirm = "drain-then-reboot"`, and a
   request without it is ignored.
3. **Requests expire.** Older than 30 minutes and the request is removed without acting, so a forgotten file
   cannot fire hours later.

The coordinator also requires the word `REBOOT` typed into a prompt, because it hosts the share: a stray
restart there costs the whole fleet, not one station's slots. Verified afterwards that a stale request and an
unconfirmed request are both refused, with the boot time unchanged.
