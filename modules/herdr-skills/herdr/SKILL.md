---
name: herdr
description: "Use only when the user explicitly asks to inspect or control Herdr panes, tabs, workspaces, commands, or agents."
---

# Herdr

Herdr exposes its current workspace, tab, pane, terminal, and recognized-agent state through the `herdr` CLI.

Before any Herdr inspection or control command, require:

```bash
test "${HERDR_ENV:-}" = 1
```

If it fails, state that this agent is not running inside Herdr and stop. Never inspect or control the focused Herdr session from outside Herdr.

The installed CLI is authoritative. Use `herdr --help`, then print the relevant non-mutating command group (`herdr agent`, `herdr pane`, `herdr workspace`, `herdr tab`, `herdr worktree`, `herdr terminal`, `herdr notification`, `herdr integration`, `herdr session`, or `herdr machine`). Do not run bare `herdr`, which launches or attaches the TUI. Do not probe a mutating nested command by omitting arguments; some commands, including `herdr workspace create`, execute with defaults.

Route to the relevant detail:

- [CLI context and targeting](references/targeting.md): identifiers, caller context, machine/session boundaries, discovery, and topology.
- [Agent coordination](references/agents.md): starting, prompting, waiting for, reading, and interacting with recognized agents.
- [Pane commands and safety](references/panes-and-safety.md): ordinary commands, output capture, focus, destructive operations, repository trust, and server boundaries.

Across all workflows:

- Prefer `--current`, an explicit pane ID, or a unique live agent name. Omitting a target may act on the user’s or another client’s focused pane.
- Parse opaque IDs and state from command JSON; never predict them from examples or sidebar order.
- Use `--no-focus` for background work unless the user asked to switch context.
- Inspect before responding to a blocked UI. Never answer an approval or question prompt without the user’s direction.
- Do not close resources you did not create, alter machine profiles, grant repository trust, replace or stop a server, or kill pane processes unless the user explicitly requested that action.
