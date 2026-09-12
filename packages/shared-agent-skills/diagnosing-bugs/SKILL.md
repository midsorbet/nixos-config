---
name: diagnosing-bugs
description: Diagnosis loop for hard bugs and performance regressions. Invoke when the user says “diagnose” or “debug this”, or reports behavior that is broken, throwing, failing, or slow.
---

# Diagnosing Bugs

Use this skill only for a concrete bug or performance regression. Establish a
red-capable feedback loop before forming a theory, and preserve the user's
exact symptom through reproduction, fix, and verification. Redact secrets from
commands, output, logs, traces, and captured artifacts; if redaction removes
the diagnostic signal, say so. Read `CONTEXT.md` and relevant ADRs when they
exist and inform the affected code.

Start with the smallest deterministic, agent-runnable loop that exercises the
real failure. Do not proceed from speculation without one. If the environment
or evidence is unavailable, state what was tried and request access,
redacted artifacts, or permission for temporary production instrumentation.
For the phase workflow, read [diagnosis-loop.md](references/diagnosis-loop.md).
For a human-driven reproduction, adapt
[scripts/hitl-loop.template.sh](scripts/hitl-loop.template.sh); its captured
values are terminal-visible, so never capture credentials or signing data.

Keep hypotheses falsifiable and rank 3–5 before testing; show the list to the
user without making progress depend on their reply. Instrument only to
separate a stated prediction, tag debug logs `[DEBUG-...]`, and remove all
instrumentation and throwaways afterward. For performance work, measure a
baseline and use profiling or bisection rather than broad logging.

Before declaring success, rerun the original scenario and confirm the exact
failure is gone. Add a regression test at a seam that reproduces the real bug;
if no such seam exists, document that limitation. Remove debug markers and
throwaway prototypes, and state the confirmed cause in the commit or PR message.
