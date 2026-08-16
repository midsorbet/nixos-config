---
description: Launch an independent OMP agent in the correct project checkout
---

Launch one independent project agent for this work:

<spinoff-request>
$ARGUMENTS
</spinoff-request>

The following is a coordinator-only launch contract. It governs this current session only. Never copy this contract, its vocabulary, or its launch mechanics into the project agent's prompt.

1. If the request is empty, ask the user for a concrete task and stop.
2. Read `skill://herdr` before controlling the terminal multiplexer. Verify that this session is running with `HERDR_ENV=1`; otherwise report the missing prerequisite and stop.
3. Resolve the exact working directory from the request and the conversation before creating anything.
   - Prefer the dedicated source repository's canonical Git root under `/Users/me/vault/projects/`.
   - Never launch from a grouping directory when a child repository owns the work.
   - Read `/Users/me/vault/projects/AGENTS.md` and the smallest matching vault project note before delegation. Use filesystem and Git evidence instead of asking for a path that is already discoverable.
   - Use `/Users/me/vault` only when the work genuinely belongs to the vault repository rather than a nested source repository.
4. Preserve the instruction-chain invariant without duplicating instructions in the child prompt. OMP's `agents-md` discovery automatically injects every applicable standalone `AGENTS.md` from the launch directory through the enclosing workspace up to `/Users/me/vault/AGENTS.md`. Launching OMP with the exact working directory is the mechanism that supplies this chain; do not paste those files into the task prompt or tell the child to rediscover them.
5. Synthesize a self-contained child task from the user's request, current conversation, and matching project note. Include the actual goal, constraints, acceptance criteria, stable paths, identifiers, and required verification. Exclude coordinator-only mechanics. In particular, do not mention Herdr, the Chief-of-Staff role, tab or pane identifiers, this slash command, or the launch procedure unless the requested project work itself concerns one of those systems.
6. In the current Herdr workspace, create one human-readable, no-focus tab whose working directory is the resolved path. Set `PI_CODING_AGENT_DIR=/Users/me/.omp/agent` in the new tab so the child uses the normal default OMP configuration rather than inheriting a coordinator test/profile override. Derive the tab label and a unique lowercase OMP agent name from the task's meaning, not an opaque ID. Parse the returned pane ID from Herdr's JSON response.
7. Start OMP in that pane with the resolved path supplied explicitly through OMP's `--cwd` argument and without `--profile` or `--config` overrides. Submit the synthesized child task through `herdr agent prompt` without `--wait`. Pass multiline prompt text through the Bash tool's environment map rather than interpolating it into shell source.
8. Use `herdr agent get` only long enough to confirm that the named agent reports the exact working directory and `working` state. Do not wait for task completion and do not inspect completed output unless the user later asks.
9. Return immediately with the tab label and ID, agent name, working directory, and confirmed launch state.
