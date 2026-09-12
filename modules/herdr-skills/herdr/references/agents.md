# Agent coordination

Default to a sibling pane in the current tab and current working directory. Create a workspace, tab, worktree, or different cwd only when the user requests that topology or location.

Honor a requested split direction. Otherwise inspect the caller:

```bash
herdr pane layout --pane "$HERDR_PANE_ID"
```

Split a wide pane right and a narrow or tall pane down; preserve cwd and user focus:

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

Read the new pane ID from `.result.pane.pane_id`. The target must be an available shell at its interactive prompt, with no foreground command, editor, or agent.

Start the requested supported kind with a useful unique name:

```bash
herdr agent start reviewer --kind codex --pane <returned-pane-id>
herdr agent start reviewer --kind codex --pane <returned-pane-id> -- <agent-args...>
```

Use `herdr agent` for installed kinds and options. `agent start` does not create or move layout. Success means Herdr detected the expected agent in the same pane and found it ready. Startup defaults to 30 seconds. If startup returns `agent_not_ready` because the agent is blocked, its name remains usable by `agent read` and `agent send-keys`; inspect it and wait for `idle` before prompting.

Submit work through the agent surface:

```bash
herdr agent prompt reviewer "Review the current diff and report only actionable findings." --wait --timeout 120000
```

`agent prompt` sends text and Enter as one ordered submission. Successful submission alone does not prove a turn started. It rejects a recognized approval/question state with `agent_blocked`; inspect that UI and ask the user before answering it.

For ordinary work, `--wait` settles on the first `idle`, `done`, or `blocked` state after observed `working` or `blocked` activity. A prompt from a non-working state has five seconds to show activity, otherwise it returns `agent_prompt_stalled`; a caller deadline returns `timeout`. A stalled or timed-out response does not prove the prompt was not delivered, so inspect before resubmitting. Without `--timeout`, the settled-state wait is indefinite after activity begins. If the agent was already working, completion of that active turn may satisfy the wait.

Use `--until` only for a state-specific workflow:

```bash
herdr agent wait reviewer --until blocked --timeout 120000
```

Standalone `agent wait` without `--until` uses the same settled-state defaults. For interactive controls, use validated logical keys:

```bash
herdr agent send-keys reviewer esc
herdr agent send-keys reviewer ctrl+c
```

Inspect results through the resolved agent:

```bash
herdr agent get reviewer
herdr agent read reviewer --source recent-unwrapped --lines 120
```

If a wait fails or returns `blocked`, inspect both commands before deciding what to send. Use pane commands only when raw terminal control is intentional.
