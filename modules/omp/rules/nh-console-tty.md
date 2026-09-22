---
description: Route approved nh switches through OMP's visible console TTY.
condition:
  - '\bnh[ \t]+(?:os|darwin)[ \t]+switch\b'
scope:
  - tool:bash
  - tool:eval
  - tool:hub
interruptMode: always
---

Run `nh os switch` and `nh darwin switch` with the foreground `bash` tool and
`pty: true`. Do not set `async: true`, pipe output, use a background `hub` PTY,
or route the switch through a Herdr pane. The OMP console TTY is the interactive
overlay in the current session; it does not require a separate terminal window.

Tell the user before sudo prompts and let them type directly into the console
TTY. When `HERDR_ENV=1`, immediately before the visible console TTY begins
waiting for authentication or other user input, run exactly:
`herdr notification show "OMP needs input" --body "Return to the waiting prompt" --sound request`.
The notification must not contain passwords, secrets, host-sensitive details,
or command output. If Herdr is unavailable, retain the current console behavior
without attempting a standalone fallback. If the session has no interactive UI,
stop and explain that prerequisite. Never silently fall back or create a terminal
window. Keep the repository's build-before-switch, host order, and explicit
deployment-approval boundaries.
