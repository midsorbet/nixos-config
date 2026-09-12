# Diagnosis Loop

Use these phases after the root preconditions are satisfied. Skip a phase only
with an explicit justification.

## 1. Build a red-capable loop

Choose the narrowest signal that reaches the bug: a failing test, HTTP or CLI
script, headless browser assertion, replayed trace, throwaway harness,
property/fuzz loop, bisection, differential run, or (last) the human-in-the-loop
script. The command must assert the user's exact symptom, be deterministic and
fast, and run unattended. Run it once before relying on it and record redacted
invocation/output. Tighten setup, assertions, timing, randomness, filesystem,
and network as needed. For nondeterministic failures, increase reproduction
rate with repetition, stress, or controlled timing.

If no loop can be built, stop diagnosis rather than guessing. Report attempts
and request a reproducing environment, a redacted HAR/log/core/screen artifact,
or permission for temporary production instrumentation.

## 2. Reproduce and minimise

Run the loop and verify it is the user's failure, not a neighboring error.
Repeat enough to establish reproducibility and capture the exact error, output,
or timing. Remove one input, caller, configuration, data item, or step at a
time, rerunning after each change. Keep only load-bearing elements; the minimal
loop becomes the regression candidate.

## 3. Hypothesise

Before probing, write 3–5 ranked, falsifiable hypotheses. Each must predict
what changing one variable will improve or worsen. Show the ranking to the user
as a checkpoint, but continue if they are unavailable.

## 4. Instrument and test predictions

Change one variable per probe. Prefer a debugger or REPL, then targeted logs at
discriminating boundaries; never log everything. Tag each temporary log with a
unique `[DEBUG-...]` prefix. For performance regressions, establish a baseline
with a timing harness, profiler, query plan, or bisection and measure before
fixing.

## 5. Fix and verify

Add a regression test before the fix only when a test seam exercises the real
call-site pattern. Run it red, apply the fix, run it green, then rerun the
original unminimised loop. If no correct seam exists, record that finding rather
than adding a shallow test that gives false confidence.

## 6. Clean up

Confirm the original reproduction no longer occurs and the regression test
passes, or document the missing seam. Search for and remove every
`[DEBUG-...]` marker and delete throwaway prototypes (or move them to a clearly
marked debug location). State the confirmed cause in the commit or PR message.
