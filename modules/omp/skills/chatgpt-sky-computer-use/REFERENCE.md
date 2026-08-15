# ChatGPT Sky recovery branches

Read only the branch needed for the current interaction.

## iOS and iPad apps on macOS

`list_apps` may show both an installed app and a transient live wrapper with the same bundle identifier. Prefer the running wrapper's full path, normalized as `/var/folders/.../Wrapper/...` with no `/private` prefix or trailing slash.

After one fresh `list_apps`, make one attempt with the exact running wrapper path. If resolution remains ambiguous or rejected, stop trying path, name, and bundle-ID permutations. Use AppleScript/System Events, XCUITest/Appium, a copy-ready manual handoff, or bounded visible keypad interaction instead.

Before a long workflow, verify that the accessibility tree exposes usable windows, labels, actions, and committed field values. If it does not, stop early.

## Window, display, and coordinate changes

Refresh state after a window manager, Space change, display move, resize, hide, minimize, or focus transition. Derive any coordinate from the newest screenshot and never reuse it after one of those changes.

A coordinate or window-position failure invalidates that target. Refresh once and prefer a current semantic element; do not repeat the same coordinate.

## Field entry and selection

Use `set_value` only for elements exposed as settable. Otherwise click the editable element, confirm focus in the returned state, and use `type_text` or `press_key` according to the mounted schema.

Compare the returned field value with the intended value. A successful response with missing, truncated, or differently formatted text is a failed edit. Use `select_text` only when the element exposes a settable selected-text range.

## Safety-restricted apps

A Computer Use safety refusal is final for that app. Do not retry with its name, bundle identifier, or filesystem path. Switch to its CLI, a dedicated API or browser interface, or a manual handoff.

## Native adapter recovery

If `sky_computer_use` is absent after this skill was read successfully, start one fresh OMP session once so the managed adapter can load. Do not enable `chatgpt-computer-use` through `/mcp`; that restores the generic catalog this gate replaces.

If the activator succeeds but the `computer_use_*` tools remain absent, do not call it again. Report an adapter-routing failure. For an unfamiliar argument schema, read only that mounted device's `xd://` docs. If a direct call fails, report its broker, permission, routing, or safety error. The user can run `/computer-use-status` for additional signed-bridge diagnostics; do not silently escalate to native computer control.
