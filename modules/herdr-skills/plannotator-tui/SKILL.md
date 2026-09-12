---
name: plannotator-tui
description: Open a Markdown plan or document for human review in a Herdr pane when review is required before acting; returned annotations arrive as the next user message. Requires HERDR_ENV=1.
---

# Plannotator TUI

Use only from the agent’s own Herdr-managed pane:

```bash
test "${HERDR_ENV:-}" = 1
```

If unavailable, tell the human the document path and ask them to review it instead. Do not attempt to inspect or target a Herdr pane from outside Herdr.

Write the plan, spec, or design document to a file and do not duplicate it in chat. From the pane that must receive the review, run:

```bash
plannotator-tui herdr open docs/plans/auth.md
```

The configured Plannotator pane opens with delivery targeted back to the caller. End the turn immediately: do not wait, poll, or read the review pane. Feedback arrives as the next user message in numbered sections such as:

```markdown
## 1. (line 12) Feedback on: "Rotate the token on every…"
> Rotation on every privilege change will log people out…
```

Address every returned item before continuing the reviewed work.

When listing files for the human to open from Herdr, emit `file://` OSC 8 hyperlinks:

```bash
printf '\e]8;;file://%s\e\\%s\e]8;;\e\\\n' "$PWD/docs/plans/auth.md" "docs/plans/auth.md"
```

If `plannotator-tui` is not on `PATH`, preserve both the source and delivery pane explicitly:

```bash
herdr plugin pane open --plugin plannotator-tui --entrypoint doc --placement split \
  --direction right --target-pane "$HERDR_PANE_ID" --focus --cwd "$PWD" \
  --env PLANNOTATOR_TUI_FILE="$PWD/docs/plans/auth.md" --env PLANNOTATOR_TUI_DELIVER_TO="$HERDR_PANE_ID"
```
