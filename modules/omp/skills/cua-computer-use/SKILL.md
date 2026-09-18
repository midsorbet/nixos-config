---
name: cua-computer-use
description: Use Cua Driver for bounded native macOS interaction only when no dedicated API, CLI, plugin, or browser controller can complete the task.
---

# Cua computer use

Use the signed native `cua-driver` MCP server only for native macOS UI,
authorized browser chrome, accessibility semantics, authenticated desktop-only
surfaces, or visible verification. Prefer, in order, a dedicated plugin/API/CLI,
OMP's named browser controller for webpage internals, AppleScript/JXA or App
Intents for scriptable macOS apps, and XCUITest/Appium for iOS. A Cua refusal or
absence never authorizes global native control or another bypass.

## Native MCP discovery

The managed configuration registers the server as `cua-driver`. OMP discovers
its tools automatically. In Code Mode, use the advertised
`tool.mcp__cua_driver_*` methods through Eval. When tools are exposed through
`xd://`, read the catalog and the selected tool's schema before calling it.
A newly started server can finish connecting after the first request. Use only
the currently advertised tools and schemas; do not infer arguments from old Sky
behavior.

Common Cua Driver tools include `mcp__cua_driver_list_apps`,
`mcp__cua_driver_list_windows`, `mcp__cua_driver_launch_app`,
`mcp__cua_driver_get_window_state`, `mcp__cua_driver_click`,
`mcp__cua_driver_double_click`, `mcp__cua_driver_right_click`,
`mcp__cua_driver_type_text`, `mcp__cua_driver_press_key`,
`mcp__cua_driver_hotkey`, `mcp__cua_driver_set_value`,
`mcp__cua_driver_scroll`, and `mcp__cua_driver_drag`; use only tools actually
returned by discovery and only their current schemas.

Before operating, read [Native action protocol](references/native-action-protocol.md).
Read [Browser handoff and recovery](references/browser-handoff-recovery.md) only
for authorized browser chrome, stale controller recovery, permissions, or daemon
recovery.

## Authorization boundary

Native MCP access exposes a capability; it neither expands app policy nor
authorizes a consequential action.

- Production policy initially allows TextEdit (`com.apple.TextEdit`) and
  Calculator (`com.apple.calculator`). Cook Well (`com.cookwell.app`) is
  limited to its approved read-only/navigation iOS pilot: never create, edit,
  delete, save, or otherwise mutate its data.
- Any added bundle ID requires explicit configuration approval. There is no
  unbounded or standard-mode fallback for an absent app.
- Resolve app identity with `mcp__cua_driver_list_apps` and resolve its exact
  PID/window with `mcp__cua_driver_list_windows`. If identity or target scope
  cannot be grounded, stop; never use a windowless desktop target, global input,
  or another foreground app as a workaround.
- Treat the driver's bounded capability manifest and returned refusal as
  authoritative. Never weaken policy, change transport/profile, or substitute a
  different tool to bypass it.

Immediately before sending, publishing, uploading, downloading, deleting,
purchasing, accepting terms, authenticating, transmitting credentials,
changing permissions/security, or disclosing private data, inspect the target
and obtain confirmation for the exact values. Perform only that action in a
separate tool call, then inspect again. Prior task approval and app allowlisting
are not confirmation.

## Privacy and lifetime

The managed launcher starts the exact signed `/Applications/CuaDriver.app` with
bounded manifest permissions and refuses an expired or conflicting daemon. It
disables telemetry and startup update checks; do not re-enable them, run
autonomous updates, persist computer history, or add a network transport. The
signed app owns macOS Accessibility and Screen Recording grants. Never widen TCC
permissions or operate the permission UI. A transport disconnect does not
promise that a separately running daemon stops.
