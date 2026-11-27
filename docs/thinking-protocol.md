# Thinking protocol (draft)

How to spend effort so that each step buys evidence. Derived from the 2026-11-27 session, where three
substantive claims were wrong and every one failed the same way: a plausible story was formed, then
checked for confirmation instead of being attacked.

Status: P1 and P2 are adopted as R6 and R7 (AGENTS.md). P3-P8 remain advisory drafts.

## P1 - Falsify before explaining

Before writing a fix or a causal claim, state the observation that would disprove it, and obtain that
observation first.

Worked example: the claimed `?`-operator bug in `ready_with_strides` survived review and was written up
as a proposal. One mutation test - restore the old line, expect red - showed the test passed either way,
so the explanation was wrong and the real divergence was the unset-lock case. Cost of skipping this:
a wrong proposal, a wrong commit message, and a rewritten document.

## P2 - Ask the question that separates two live hypotheses

One hypothesis produces runs that confirm or fail ambiguously. Two hypotheses, chosen so that one
observation distinguishes them, produce a decision.

Worked example: "why is the frame black" produced three inconclusive runs. "Do the draws write to the
target we dumped, or elsewhere?" was answerable in one run with `VICTORY_LOG=victory_gpu::draw=debug`,
and it killed the fallback-descriptor theory immediately.

## P3 - Predict, then measure

Write the expected numbers before the experiment. A mismatch is a finding; without a prediction, every
outcome is absorbed into the story.

Worked example: "shaders should jump from 21 to hundreds when the world loads" turned a black screen
into a measurable claim about whether the title had even reached the world.

## P4 - Prior art before hypothesis

Search the trackers and the docs for the symptom before constructing a theory. Someone has often
already staged the problem.

Worked example: issue #445 already documented black-world-on-NVIDIA with a stage distinction
(G-buffer drawn, lighting zeroed) that took this session hours to rediscover - and which showed our
failure was at an *earlier* stage than the documented one.

## P5 - Convert descriptions into artefacts

A pixel value, a log line, a file listing. When a claim rests on a description of a screen, a status
or an exit code, it is not yet evidence.

Worked example: "black screen" was interpreted for hours. `RGB(0,0,0) A=255` at four frame numbers
settled in one step that the renderer, not the display path, produced black.

## P6 - Keep a hypothesis ledger

For each live hypothesis, record: statement, evidence for, evidence against, status, next discriminating
test. Without it, overturned theories get re-proposed - today's `?` theory was argued twice before the
mutation test settled it.

## P7 - Timebox a theory that is not producing evidence

If a hypothesis has survived N steps without a new measurement, either design a sharper test or drop
it. Prolonged reasoning about an untested theory is the expensive failure mode, not the wrong answer.

## P8 - Separate belief from measurement in every report

Mark claims as measured, inferred, or unverified. The reports that went wrong today were the ones where
an inference was written in the voice of a measurement.

## What this does not fix

Thinking faster is not the goal. Two of the three wrong claims were cheap to correct precisely because
the system was instrumented. The expensive ones were cheap to *prevent* with P1 and P2. Nothing here
makes a hypothesis right; it makes a wrong one cost minutes instead of hours.