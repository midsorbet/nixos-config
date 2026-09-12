# Browser handoff and recovery

## Named browser handoff

Keep webpage internals in OMP's browser controller. Cua must not attach to an
existing profile by default. Browser chrome is eligible only when the user
requested work on it and that browser's bundle ID is explicitly approved; the
initial app policy authorizes no browser.

For an authorized chrome action:

1. Keep the same named controller and tab after interactive sign-in; never adopt
   an arbitrary visible tab.
2. Close that controller to release it, then resolve the approved browser PID and
   exact window for Cua.
3. Reopen the same name and recover the same tab afterward. If this reports
   `Network.enable` and `Debugger is not attached to the tab`, release the
   stale controller and recover the configured relay/debugger attachment before
   reopening that same name. Do not adopt another tab.

Existing-profile preparation or attachment is not implicit recovery; profile
access needs separate explicit authorization.

## Permissions

If the signed app lacks Accessibility or Screen Recording permission, ask the
user to run:

```text
/Applications/CuaDriver.app/Contents/MacOS/cua-driver permissions grant
```

The user must approve the system prompts; never control that UI for them.

## Failed calls and daemon recovery

A failed call ends that exact strategy. Retry only with changed state, target,
arguments, or method, after refreshing app/window identity and snapshot. A wrong
visible value is a failed edit. After a second changed-precondition failure, use
the next permitted interface or give a precise manual handoff.

For an expired or conflicting daemon, do not add flags or weaken policy. Stop
the user-owned daemon with the exact signed binary, then reactivate:

```text
/Applications/CuaDriver.app/Contents/MacOS/cua-driver stop
```

The launcher intentionally refuses to stop or replace a daemon silently.
