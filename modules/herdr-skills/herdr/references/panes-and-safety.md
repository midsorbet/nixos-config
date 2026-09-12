# Pane commands and safety

For an ordinary command, create a sibling pane while preserving cwd and focus:

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
herdr pane run <returned-pane-id> "just test"
herdr pane wait-output <returned-pane-id> --match "test result" --timeout 120000
herdr pane read <returned-pane-id> --source recent-unwrapped --lines 120
```

`pane run` atomically submits command text and Enter. `pane wait-output` checks the current snapshot immediately; existing output may match. Use `--match` for a literal substring or `--regex` for a Rust regular expression. Without `--timeout`, waiting is indefinite.

Choose output deliberately:

- `visible`: rendered viewport.
- `recent`: recent rendered output including soft wraps.
- `recent-unwrapped`: recent output with soft wraps joined; preferred for logs and transcripts.
- `detection`: bottom-buffer plain text used for agent detection.

Use `--format ansi` only when styling is evidence; otherwise use text. `--lines` can request more screen/host-scrollback rows, but alternate-screen rows that have disappeared cannot be recovered. After confirming that limitation, ask the agent to write its complete response to a temporary Markdown file and return only its path, then read the file directly. This is a fallback, not an initial prompt requirement.

## Destructive and privileged boundaries

- Do not close workspaces, tabs, panes, or sessions you did not create without an explicit user request.
- `workspace close --group` closes the primary workspace and linked worktree workspaces. Never add it merely to bypass `workspace_group_close_required`.
- `--trust-repository` grants per-request Git trust. Use it only after the user verifies the repository, never as a routine retry.
- Check `herdr status` before relying on new server features when client/server versions may differ. A missing method is not permission to stop or upgrade the server.
- Never run `herdr server stop` from an active session unless the user explicitly intends to stop the server and its pane processes.
- Never kill the main Herdr process. Experiments requiring isolation use named test sessions.
- CLI server errors are JSON on stderr with exit status 1; syntax errors exit with status 2.
