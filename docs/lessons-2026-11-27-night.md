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
