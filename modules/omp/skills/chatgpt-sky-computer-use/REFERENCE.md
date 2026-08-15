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

## Catalog or bridge recovery

If the user enabled the server but no Sky devices mounted, start one fresh OMP session once. Do not guess device URIs or invoke the MCP executable directly.

If devices mounted but calls fail, use `computer_use_status` when available. Report a broker, permission, or transport failure rather than silently escalating to native computer control.
