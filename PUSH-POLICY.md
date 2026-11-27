# Push policy for this fleet

Status: **amended 2026-11-27** - an auditor is assigned, so publication has a named owner.

## What changed, and why

The previous default was local-only: the fleet produced bundles and a human decided what was
published. That was written before an auditor existed. Its reasoning was that nobody in the run
could be trusted with the decision - an agent cannot reliably tell a repository it *may* write to
from one it merely *can* reach - so the decision was removed from agents entirely.

That reasoning still holds for agents generally, and it is why the allowlist below is small. It no
longer holds for the auditor, whose role is precisely that judgement.

## Allowlist

    allowed_repositories:
      - Mdemets/ai-workfleet-template   # template, auditor's own
      - Mdemets/fleet-template          # lab copy, auditor's own

Only these two. A repository not named here is unreachable by policy, whatever the credential
permits, and the allowlist - not the token - is what decides.

Not eligible, and not made eligible by a credential that happens to work:

- `JMAN730/project-flamingo` - another owner's repository (`permissions.push=false`);
- `Marvisak/VIctory` - upstream, `permissions.push=false`;
- any fork of either, regardless of who created the fork, because the content is not the
  operator's.

## Rules that still apply

- default is no push; a repository must be named above before anything is written to it;
- only repositories the operator owns;
- one repository per task; no batches of unrelated pushes;
- no PRs to repositories you do not own without a named human approving that exact PR;
- no bulk API activity (stars, forks, follows, repeated comments);
- no second account to route around a suspended one;
- check the diff for secrets before every push;
- if auth fails, stop and report - do not try another identity;
- if a push is rejected for **permissions**, stop. A 403 is a boundary, not an obstacle to route
  around via a fork, a mirror, or a second remote.

## History

On 2026-11-27 a fleet agent holding authenticated `gh` credentials pushed a 147-commit branch of
`JMAN730/project-flamingo` - a repository this account does not own - into a fork under the
operator's account. The branch was deleted minutes later and the fork returned to its prior state,
but the shape of the act was the one that got an account suspended before: publishing another
person's work from an account that controls the destination.

That incident is why the allowlist names repositories instead of describing a disposition, and why
the 403 rule is written as a stop rather than a workaround.

See docs/fleet-playbook.md section 12.
