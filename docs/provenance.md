# Provenance: why this template exists

This did not start as an infrastructure project. It started because one person wanted to run a
demanding Windows title **natively** across several workstations, and that work needed somewhere to
happen that was honest about what each machine had actually done.

## The projects that made it necessary

| Project | What it gave this work |
|---|---|
| [Marvisak/VIctory](https://github.com/Marvisak/VIctory) | the upstream effort to run the title natively; the reason there was anything to test at all |
| [JMAN730/project-flamingo](https://github.com/JMAN730/project-flamingo) | the working fork where the multi-station work happened, and where most of the transport's requirements were discovered |

Neither project asked for this template. It exists because of theirs.

## What the template owes them

The conventions here are not invented - they were learned in those repositories and then generalised:

- **A number without its commit is not a result.** Report format: commit, adapter, driver, toolchain,
  wall time, exit code, counts, and whether another test binary was alive at the start.
- **One mutation you can name makes a test go red.** A green suite that never had a red state certifies
  nothing.
- **One writer per branch, one deliverable per lane.** Parallelism that shares a working tree produces
  merge chaos, not throughput.
- **The coordinator owns the code; changes are proposed.** Learned the hard way, and now R1.
- **Report the failure rather than weakening the test.** The board is not the goal.

The distance between a workstation and a fleet is mostly bookkeeping: who ran what, on which machine,
against which commit, and did it survive being checked. That bookkeeping culture came from the two
projects above.

## The incidents that shaped the rules

Every rule in `AGENTS.md` has an incident behind it, recorded in `docs/lessons-2026-11-27.md`. Three
stand out:

- A credential rotation left a running worker holding a dead password; its retries locked the account
  and the fleet went down for reasons nobody could see in any log. (R2's sibling: verify from the
  process's context.)
- A reboot to repair a WMI provider was proposed without a way back; the machine did not return and
  recovery waited for a human. (R4.)
- A bundle carrying four merges existed only on the machine that then failed. (R5.)

## Thanks

To the maintainers and contributors of both projects, and to the people who filed the reports this
fleet's investigations leaned on - measurement dossiers with real numbers are rare and enormously
more useful than opinions.

If you have several workstations sitting idle, this is what one looks like when it is put to work.

## If you want to share this

Please share the link, not a comment on someone else's tracker - an unsolicited template link in an
issue thread is spam by most maintainers' definition, and it reflects on the projects credited above.

    https://github.com/Mdemets/ai-workfleet-template