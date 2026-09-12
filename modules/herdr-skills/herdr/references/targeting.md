# CLI context and targeting

Herdr’s layout hierarchy is workspace → tab → pane. A pane may contain a shell, ordinary process, or recognized agent. Pane commands control terminals; agent commands validate and address the recognized coding agent occupying a pane.

Public IDs are opaque stable handles such as workspace `w1`, tab `w1:t1`, and pane `w1:p1`. Closed tab and pane IDs are not reused. A moved pane receives a new workspace-qualified ID: after `herdr pane move`, use `.result.move_result.pane.pane_id` or the live agent name. `.result.move_result.previous_pane_id` is not a general target; only the moved process’s inherited caller context continues resolving it.

Each managed pane inherits:

```bash
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
```

Discover current state without relying on UI focus:

```bash
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane current --current
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
```

Creation responses provide subsequent targets: `workspace create` returns `.result.workspace`, `.result.tab`, and `.result.root_pane`; `tab create` returns `.result.tab` and `.result.root_pane`; `pane split` returns `.result.pane`.

## Agent targets and lifecycle

Agent commands accept a unique live agent name or the pane ID hosting that agent, not a terminal ID or bare agent-kind label. Names match `[a-z][a-z0-9_-]{0,31}` and are unique among live agents. A name follows the pane occupant and clears when that agent exits, is released, or is replaced.

Lifecycle states have precise limits:

- `idle` and `done` both mean ready for input. Server seen-state distinguishes them; explicit focus marks a target seen, while reads do not. TUI clients track viewed completions independently.
- `blocked` means Herdr recognized an approval or question UI.
- `unknown` means an agent is present but Herdr cannot classify it confidently; it does not prove completion.

## Machine and session boundaries

IDs and live names are scoped to one server. Selecting another machine in the TUI does not retarget CLI commands in the caller pane; they retain inherited session/socket context. Run remote commands on the intended host with its explicit session, then rediscover identifiers there.

`herdr machine list` reports saved profiles, not cross-machine panes; use `--json` for scripts. Only add, remove, enable, or disable profiles at the user’s request. Removing a profile disconnects the client but does not stop remote sessions. `machine add` uses the remote default session unless `--remote-session` is supplied. Setup defaults to No before stopping an incompatible server; never approve replacement without user consent. Experimental handoff is not part of `machine add`.
