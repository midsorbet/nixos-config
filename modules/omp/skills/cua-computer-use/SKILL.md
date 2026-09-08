---
name: cua-computer-use
description: Use Cua Driver for bounded native macOS interaction only when a dedicated API, CLI, or browser interface cannot complete the task.
---

# Cua Computer Use

Use the signed native `cua-driver` stdio MCP server through OMP's one-turn gate. This workflow has no Sky API compatibility layer, nested model, HTTP server, existing-browser-profile default, or broad always-on desktop authority.

## Route before activation

Use the first suitable interface:

1. Use a dedicated plugin, MCP server, API, or CLI.
2. Use OMP's named browser controller for webpage internals.
3. Use Cua only for native macOS UI, authorized browser chrome, accessibility semantics, authenticated desktop-only surfaces, or visible verification.
4. Use AppleScript/JXA or App Intents/Shortcuts for scriptable macOS apps.
5. Use XCUITest/Appium for iOS Simulator or device workflows.

Do not enable OMP's global native computer control as a fallback merely because Cua is unavailable or refuses an action. Use another suitable interface or give a precise manual handoff.

## Activate for one assistant turn

Call the mounted `cua_computer_use` activator once with `{}`. If OMP mounts it at `xd://cua_computer_use`, write JSON content `{}` to that device. Do not ask the user to enable it.

The extension initially exposes only this activator. Its SDK transport, native-tool catalog, and Cua Driver connection load only on activation; no Cua MCP server is configured at startup. Call the exposed native tools directly. There is no `computer_use({code})` wrapper or JavaScript `sky` environment. After the assistant turn, the native tools become inactive and the transport closes. The activator remains available for a later turn.

The live MCP `tools/list` response and each mounted tool's current input schema are the authority for available operations. Never invent a tool or argument from old Sky behavior. Cua 0.24.0 core names include `list_apps`, `list_windows`, `launch_app`, `get_window_state`, `click`, `double_click`, `right_click`, `type_text`, `press_key`, `hotkey`, `set_value`, `scroll`, and `drag`; use only tools actually mounted this turn.

## Independent authorization boundaries

Activation is only a short-lived capability exposure. It does not widen the native application policy or authorize a consequential action.

- Production runs use the bounded app allowlist. Its initial entries are TextEdit (`com.apple.TextEdit`), Calculator (`com.apple.calculator`), and Cook Well (`com.cookwell.app`). Cook Well is limited to the approved read-only/navigation iOS pilot; never create, edit, delete, save, or otherwise mutate its data. Each activation and its transport-owned driver session have finite lifetimes; transport close or idle expiry cleans up the native session.
- Added bundle IDs require explicit configuration approval. There is no standard-mode or unbounded fallback when an app is absent.
- Cua 0.24.0's native runtime enforces the manifest's app and window scope for observation and native actions, but `launch_app` does not enforce the manifest's app resource grant. The OMP gate therefore accepts `launch_app` only with an explicit allowlisted `bundle_id`; it rejects name-only and nonlisted launches. This launch guard is an OMP boundary, not a restriction provided by direct use of the raw Cua CLI.
- Target only an allowed app's exact PID and window. Do not use windowless desktop targets, global keyboard input, global clicks, or another foreground app to work around policy.
- Treat a Cua policy or safety refusal as final. Never weaken policy, change transport, attach through another profile, or use a different tool to bypass it.

Before any send, publish, upload, download, deletion, purchase, acceptance of terms, authentication step, credential transmission, permission change, security change, or disclosure of private data, inspect immediately and obtain the user's confirmation for the exact target and values. Perform that one consequential action in a separate tool call, then inspect again. Earlier task approval, Cua activation, and app allowlisting are not that confirmation.

## Native action loop

1. Resolve the allowed app with `list_apps`; launch it by its explicit allowed `bundle_id` only when necessary.
2. Resolve the exact `pid` and `window_id` with `list_windows`. A PID-only target is acceptable only when the driver proves that PID has exactly one eligible window; otherwise choose an explicit window.
3. Call `get_window_state` once per turn for that `(pid, window_id)` before an element action. Ground on both `structuredContent.elements` and the returned screenshot.
4. Prefer the current opaque `element_token`. If using `element_index`, include its matching `snapshot_id`. A later snapshot replaces the index map; stale or mismatched tokens must fail closed, not be retried against another window.
5. Prefer a background accessibility action. Use screenshot-relative pixels only when the renderer or a custom-drawn surface is absent or unreliable in AX. Use `delivery_mode: "foreground"` only explicitly for the single action that did not land in background; it may briefly foreground the exact window and then restore the prior app.
6. Reinspect after navigation, reload, modal, window, Space, display, focus, or target-app changes; after every failed or unverifiable action; and whenever the result is uncertain. Never batch an action across one of those state changes.
7. Verify the visible postcondition, not merely a success-like action envelope. For Catalyst, Electron, Chromium, and other echo-prone renderers, use the fresh screenshot as verification rather than trusting AX value echoes. Reinspect after pixel or foreground actions because those are not AX-verified.

Cua has no documented semantic `select_text` parity with Sky. Use only mounted native operations and visible postconditions. For `press_key`, supported Cua 0.24.0 names are `return`, `tab`, `escape`, `up`, `down`, `left`, `right`, `space`, `delete`, `home`, `end`, `pageup`, `pagedown`, `f1`–`f12`, letters, and digits. Supported modifiers are `cmd`/`command`, `shift`, `option`/`alt`, `ctrl`/`control`, and `fn`. A `hotkey` orders modifiers first and one non-modifier last.

## Named browser handoff and recovery

Keep webpage work in OMP's browser tool. Cua must not attach to an existing browser profile by default. Browser chrome is eligible only when that browser's bundle ID is explicitly approved in the bounded policy and the user requested work on that surface; the initial policy does not authorize a browser.

Treat every named OMP browser controller as owned state:

1. After interactive sign-in, keep the same browser name and tab; never adopt an arbitrary visible tab.
2. Before an authorized Cua browser-chrome action, close that same named browser controller to release it. Resolve the approved browser PID and exact window before acting.
3. Reopen the same browser name and recover the same tab after native work. If opening reports `Network.enable` and `Debugger is not attached to the tab`, do not retry the unchanged name and target. Release the stale controller, recover the configured relay/debugger attachment, then reopen the same named controller rather than adopting another tab.

Do not call Cua's existing-profile preparation or attachment path as an implicit recovery step. Browser-profile access requires its own explicit authorization and is outside ordinary native-window control.

## Permissions and managed privacy

On macOS, the release daemon runs as the signed `/Applications/CuaDriver.app` identity. Accessibility and Screen Recording grants belong to the user and that signed app. Tool calls must not prompt for or widen TCC permissions. If grants are missing, ask the user to run `/Applications/CuaDriver.app/Contents/MacOS/cua-driver permissions grant` and approve the system prompts. Never control the permission UI on their behalf.

The managed module disables Cua telemetry and the separate startup update check. Do not re-enable either, run autonomous updates, persist computer history, or add another network transport. Closing the transport ends the extension connection; it does not guarantee that a separately running daemon stops.

## Recovery

One failed call ends that exact strategy. Retry only after changing the state, target, arguments, or method. Refresh app/window identity and take a new snapshot before retrying stale targets. Treat a wrong visible value as a failed edit. After a second changed-precondition failure, use the next suitable interface or provide a precise manual handoff.

If Cua Driver status reports an expired or conflicting daemon, do not add flags or weaken policy. Stop the user-owned daemon with the exact built binary command `/Applications/CuaDriver.app/Contents/MacOS/cua-driver stop`, then reactivate `cua_computer_use`. The launcher refuses to silently stop or replace a daemon.
