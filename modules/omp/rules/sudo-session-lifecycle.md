---
description: Use a visible sudo session and clean up its privileges and owned tab.
condition:
  - '\bsudo\b'
  - '\bherdr[ \t]+(?:tab|pane)[ \t]+create\b[^\r\n]{0,320}\b(?:sudo|root|admin|interactive|authentication)\b'
scope:
  - tool:bash
  - tool:eval
  - tool:write(proc://**)
interruptMode: always
---

Choose the route before the first privileged command from the expected task
shape, not from an elapsed-time guess. Use foreground `bash` with `pty: true` for
one isolated sudo command. If the task is expected to need multiple privileged
commands or a temporary root shell, read the Herdr skill, require `HERDR_ENV=1`,
and create a dedicated Herdr tab before authentication. Record its tab and pane
IDs and whether this agent created it. `nh os switch` and `nh darwin switch`
always use the OMP console TTY, never a Herdr pane.

Tell the user before authentication. Immediately before a visible console TTY
or Herdr tab begins waiting for input, make this best-effort notification attempt:

```sh
if [ "${HERDR_ENV:-}" = 1 ]; then
  herdr notification show "OMP needs input" \
    --body "Return to the waiting prompt" --sound none || true
fi
```

Notification failure must not block or reroute the administration. Never put
passwords, secrets, host-sensitive details, or command output in notifications.
The user types directly into the visible TTY; never request, relay, log, or
script a password. A background `bash` job or named service is not a substitute
for a visible prompt. If Herdr is unavailable, retain the current OMP console TTY
behavior without attempting a standalone fallback or creating a terminal window.

On success, failure, or abandonment: preserve verification output, exit the
temporary root shell, invalidate sudo credentials for the invoking user locally
and on each affected remote host, then close the Herdr tab only if this agent
created it. Do not close user-owned tabs or leave privileged sessions open while
doing unrelated work.
