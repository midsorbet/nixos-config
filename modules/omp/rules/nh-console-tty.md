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

Run `nh os switch` and `nh darwin switch` in one foreground `bash` call with
`pty: true`. Prefix the switch in that same shell with:

```sh
if [ "${HERDR_ENV:-}" = 1 ]; then
  herdr notification show "OMP needs input" \
    --body "Return to the waiting prompt" --sound none || true
fi
```

The notification is best effort. Its failure must not block, replace, or reroute
the switch. Do not set `async: true`, pipe output, use a background `hub` PTY,
route the switch through Herdr, or create another terminal. Tell the user before
sudo prompts and let them type directly into the OMP console TTY. Keep the
repository's build-before-switch, host-order, explicit approval, and cleanup
boundaries.
