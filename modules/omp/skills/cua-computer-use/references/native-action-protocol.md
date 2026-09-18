# Native action protocol

Use this protocol only after the root skill's routing and authorization checks.

1. Discover the currently available MCP tools, then use the direct Eval names
   `mcp__cua_driver_*` and their advertised schemas. Resolve app identity with
   `mcp__cua_driver_list_apps`; launch only when needed using the current
   `mcp__cua_driver_launch_app` schema.
2. Resolve `pid` and `window_id` with `mcp__cua_driver_list_windows`. PID-only
   targeting is valid only if the driver proves exactly one eligible window.
3. Before an element action, call `mcp__cua_driver_get_window_state` once per
   turn for that target and ground on both `structuredContent.elements` and the
   screenshot.
4. Prefer the current opaque `element_token`. With `element_index`, include
   its matching `snapshot_id`. A new snapshot invalidates the old index map;
   stale or mismatched identifiers must fail closed.
5. Prefer background accessibility actions. Use screenshot-relative pixels only
   for missing or unreliable AX surfaces. Use `delivery_mode: "foreground"`
   only for the one action that failed in background; it may foreground the
   exact window briefly and restore the prior app.
6. Reinspect after navigation, reload, modal, window, Space, display, focus, or
   target-app changes; after failed or unverifiable actions; and whenever the
   result is uncertain. Do not batch across those state changes.
7. Verify the visible postcondition, not a success-like envelope. For Catalyst,
   Electron, Chromium, and other echo-prone renderers, trust a fresh screenshot
   over AX value echoes. Reinspect after pixel and foreground actions.

Cua has no documented Sky-style semantic `select_text`. In the native driver,
`mcp__cua_driver_press_key` supports `return`, `tab`, `escape`, arrows, `space`,
`delete`, `home`, `end`, `pageup`, `pagedown`, `f1`–`f12`, letters, and digits.
Modifiers are `cmd`/`command`, `shift`, `option`/`alt`, `ctrl`/`control`, and
`fn`; `mcp__cua_driver_hotkey` orders modifiers first and one non-modifier last.
