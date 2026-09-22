---
description: Use a visible sudo session and clean up its privileges and owned tab.
condition:
  - '\bsudo\b'
scope:
  - tool:bash
  - tool:eval
  - tool:hub
interruptMode: always
---

For repeated sudo administration, read the Herdr skill and check `HERDR_ENV=1`.
Prefer a dedicated Herdr tab. Record its tab and pane IDs and whether this agent
created it. Keep a temporary root shell only for the approved administration.
For one-off sudo, use foreground `bash` with `pty: true`. `nh os switch` and
`nh darwin switch` always use the OMP console TTY, not a Herdr pane.

Tell the user before authentication. When `HERDR_ENV=1`, immediately before the
visible console TTY or Herdr tab begins waiting for authentication or other user
input, run exactly:
`herdr notification show "OMP needs input" --body "Return to the waiting prompt" --sound request`.
The notification must not contain passwords, secrets, host-sensitive details,
or command output. The user types directly into the visible TTY; never request,
relay, log, or script a password. A background `hub` PTY is not a substitute for
a visible prompt. If Herdr is unavailable, retain the current OMP console TTY
behavior without attempting a standalone fallback or creating a terminal window.

On success, failure, or abandonment: preserve verification output, exit the
temporary root shell, invalidate sudo credentials for the invoking user locally
and on each affected remote host, then close the Herdr tab only if this agent
created it. Do not close user-owned tabs or leave privileged sessions open while
doing unrelated work.
