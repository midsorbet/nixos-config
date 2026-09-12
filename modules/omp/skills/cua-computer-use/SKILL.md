---
name: cua-computer-use
description: Use Cua Driver for bounded native macOS interaction only when no dedicated API, CLI, plugin, or browser controller can complete the task.
---

# Cua computer use

Use the signed native `cua-driver` stdio MCP server only for native macOS UI,
authorized browser chrome, accessibility semantics, authenticated desktop-only
surfaces, or visible verification. Prefer, in order, a dedicated plugin/API/CLI,
OMP's named browser controller for webpage internals, AppleScript/JXA or App
Intents for scriptable macOS apps, and XCUITest/Appium for iOS. A Cua refusal or
absence never authorizes global native control or another bypass.

## One-turn activation

Call `cua_computer_use` once with `{}`; when mounted at
`xd://cua_computer_use`, write `{}` there. The extension initially exposes
only this activator, loads the signed driver's stdio transport and native tools
on demand, and closes them after the turn. It has no Sky compatibility layer,
nested model, HTTP server, JavaScript `sky` environment, or
`computer_use({code})` wrapper.

The current MCP `tools/list` and mounted input schemas are authoritative. Do
not infer tools or arguments from old Sky behavior. Cua 0.24.0 commonly exposes
`list_apps`, `list_windows`, `launch_app`, `get_window_state`, `click`,
`double_click`, `right_click`, `type_text`, `press_key`, `hotkey`,
`set_value`, `scroll`, and `drag`; use only what is mounted this turn.

Before operating, read [Native action protocol](references/native-action-protocol.md).
Read [Browser handoff and recovery](references/browser-handoff-recovery.md) only
for authorized browser chrome, stale controller recovery, permissions, or daemon
recovery.

## Authorization boundary

Activation exposes a capability; it neither expands app policy nor authorizes a
consequential action.

- Production policy initially allows TextEdit (`com.apple.TextEdit`) and
  Calculator (`com.apple.calculator`). Cook Well (`com.cookwell.app`) is
  limited to its approved read-only/navigation iOS pilot: never create, edit,
  delete, save, or otherwise mutate its data.
- Any added bundle ID requires explicit configuration approval. There is no
  unbounded or standard-mode fallback for an absent app.
- Cua 0.24.0 enforces manifest app/window scope for observation and native
  actions, but raw `launch_app` does not enforce the app resource grant. OMP's
  gate therefore accepts it only with an explicit allowlisted `bundle_id` and
  rejects name-only or nonlisted launches.
- Target an allowed app's exact PID and window. Never use windowless desktop
  targets, global keyboard/click input, or another foreground app as a workaround.
- Treat policy and safety refusals as final. Never weaken policy, change
  transport/profile, or substitute a different tool to bypass them.

Immediately before sending, publishing, uploading, downloading, deleting,
purchasing, accepting terms, authenticating, transmitting credentials,
changing permissions/security, or disclosing private data, inspect the target
and obtain confirmation for the exact values. Perform only that action in a
separate tool call, then inspect again. Prior task approval, activation, and app
allowlisting are not confirmation.

## Privacy and lifetime

Each activation and transport-owned driver session is finite; transport close or
idle expiry cleans up that session. The signed
`/Applications/CuaDriver.app` owns macOS Accessibility and Screen Recording
grants. Never widen TCC permissions or operate the permission UI. The managed
module disables telemetry and startup update checks; do not re-enable them, run
autonomous updates, persist computer history, or add a network transport.
Transport close does not guarantee a separately running daemon stops.
