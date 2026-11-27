# Task creation: keeping a fleet fed without manufacturing work

A fleet does not idle because it is slow. It idles because nothing is writing to `queue/`. This
document is the supply side: where work comes from, how it is shaped, and how to avoid the two
failure modes - starvation and theatre.

## The supply loop

    source (issues, checks, requests, inputs)
      -> backlog cache        a file the coordinator can read without a network dependency
      -> finder               turns backlog items into task documents
      -> queue/               the handoff buffer
      -> stations             claim, execute, write a result
      -> results/             one document per dispatch

Measured end to end on three stations: ~40 dispatches/s created against ~26 completions/s of
capacity, with the queue holding at a few hundred rather than draining to zero.

## Cache the source; never depend on it at runtime

The coordinator's first version called GitHub on every pass. Unauthenticated that is 60 requests
an hour, and it was spent in minutes: every dispatch attempt became `unreachable`, and the fleet
looked idle while the real cause was a rate limit. Copy the source into a file once (1,027 open
issues and 1,711 open PRs at the time of writing) and dispatch from the copy. Refresh the copy on
its own schedule; the execution loop must never block on a network call.

## Shape the task for the machine that will run it

Two knobs, and they trade against each other:

| knob | effect |
|---|---|
| items per task | longer tasks, fewer claims, higher measured utilisation |
| tasks per pass | faster queue growth, more claim traffic |

A dispatch that finishes in 200 ms is shorter than the claim round-trip over SMB, so slots sit
idle between claims and utilisation reads low no matter how much work exists. Batch several items
per task before concluding a station is under-used.

## The high-water mark is the queue's real level

A queue's depth is set by its refill trigger, not by how much work is waiting. Measured here: the
finder targeted 1,200 queued tasks while the feeder only called it below 48, so the queue sat at
48-90 for hours and every downstream figure inherited that ceiling. Raising one comparison to
1,000 moved the level from ~80 to ~600 within twenty seconds.

## Do not manufacture load

The failure mode of a 'keep the fleet busy' rule is tasks that exist to be counted. If the backlog
is exhausted, the honest options are: re-verify on a cooled-down cycle, add a real source, or let
the fleet idle. Re-dispatching the same items at full speed inflates `created` and teaches nothing;
a re-verification cycle that runs once per cooldown is defensible, a treadmill is not.

## Deduplicate with a seen-list, not with the queue

The queue drains in seconds, so it cannot answer 'was this already dispatched'. Keep a plain text
seen-list beside the backlog and append to it on dispatch. It also makes the recycle explicit:
when the seen-list covers the backlog, that is a cycle boundary, and it should be logged as one.

## Reasoning tasks are a different kind

`kind=powershell` is deterministic and cheap to retry. A reasoning task has a prompt, a budget and
a credential, and its failure modes are different: an unauthenticated runtime returns 401 in
200 ms and looks like a successful dispatch. Treat 'dispatched' and 'answered' as separate states,
and never count a 401 as work done.
