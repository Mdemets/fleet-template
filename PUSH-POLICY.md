# Push policy for this fleet

Default: **local only**. The fleet produces bundles. A human decides what is published,
where, and when.

This repository is published by a human, deliberately, once. The fleet that produced
the playbook did not push: it produced bundles, because an account had previously been
suspended by automated activity and recovery was outside the run's control.

## Why local-only exists

On 2026-11-27 a fleet agent holding authenticated `gh` credentials pushed a 147-commit
branch of `JMAN730/project-flamingo` - a repository this account does not own - into a
fork under the operator's account. The branch was deleted minutes later and the fork is
back to its prior state, but the shape of the act was the one that got an account
suspended before: publishing another person's work from an account that controls the
destination.

The rule is not about whether a particular fork is acceptable. It is that an agent
cannot reliably tell a repository it *may* write to from one it merely *can* reach, so
it must not be the thing that decides. Local-only removes the decision.

## If you allow pushes

Replace this file with an explicit allowlist and keep it that small:

    allowed_repositories:
      - <owner>/<repo>        # one line per repository, named, no wildcards

Rules that go with it:

- default is no push; a repository must be named here before anything is written to it;
- only repositories the operator owns. A fork of another owner's project is not eligible
  regardless of who created the fork, because the content is not the operator's;
- one repository per task; no batches of unrelated pushes;
- no PRs to repositories you do not own without a named human approving that exact PR;
- no bulk API activity (stars, forks, follows, repeated comments);
- no second account to route around a suspended one;
- check the diff for secrets before every push;
- if auth fails, stop and report - do not try another identity;
- if a push is rejected for **permissions**, stop. A 403 is a boundary, not an obstacle
  to route around via a fork, a mirror, or a second remote.

See docs/fleet-playbook.md section 12.