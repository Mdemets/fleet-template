# What this fleet may send to other people

Written in plain language on 2026-11-27, replacing a version full of terms the operator should not
have had to learn. The rule is simple: **nothing leaves for someone else's project unless it is a
proven fix and the operator has approved that one request.**

## The three things

A **copy** is our own private duplicate of someone else's project. Keeping one is allowed and changes
nothing for them.

A **change request** asks the owner of that project to accept work from our copy. It is a question,
not an action: they can say no and nothing on their side moves.

A **comment** is a note on an existing discussion. It is not a change.

## What is allowed without asking

- Reading any public project, measuring it, and writing our findings down here.
- Keeping private copies of other people's projects.
- Publishing to the operator's own projects: `Mdemets/ai-workfleet-template` and
  `Mdemets/fleet-template`.

## What needs the operator's yes, once per request

A change request to either of these, and only these:

- `JMAN730/project-flamingo`
- `Marvisak/VIctory`

One at a time. No standing approval. No second request to the same project until the first has been
answered or withdrawn.

## A change request is allowed only if it is an actual fix

All five, or it does not go out:

1. **It reproduces.** The problem was made to happen on a named machine and build, and the evidence
   is recorded.
2. **It stops the problem.** The same case was run again after the change and the problem no longer
   happens.
3. **It does not break other things.** The project's own checks were run, and the counts are quoted.
4. **It is explained.** What changes, why, which files, what was measured, and how to undo it.
5. **It is small enough to read.** One problem, one change.

If any of those is missing, it is an observation, not a fix. Observations go out as comments, never
as change requests.

## Never

- Change someone else's project directly. Even when it is technically possible.
- Send anything to a project that is not named above.
- Send a batch of unrelated requests, or repeat the same comment across issues.
- Treat a refusal as an obstacle. A "no" from the other side ends it - no retry, no other account,
  no mirrored copy.
- Publish a fix whose evidence has expired: if the project moved since the measurement, measure again.

## Why this is written down

An agent once pushed 147 commits into a project this account does not own, uninvited. That is the
behaviour this rule exists to make impossible - not curiosity, not measurement, not a polite question
with evidence attached.
