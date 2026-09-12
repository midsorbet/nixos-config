# Prototype workflow

Use this reference only when the artifact models behavior or state.

## Bound the experience

Identify the user, critical job, scenario under review, relevant state model, and handoff point to the real product. Make navigation work within that boundary. Use dialogs only when interruption or confirmation belongs to the scenario; use transitions only to clarify continuity or state change.

Model states the scenario can reach, such as loading, empty, error, success, disabled, mobile, and domain-specific states. An asynchronous-looking action normally needs loading plus success and failure or recovery. A collection should consider empty state; a gated action should explain why it is disabled. Do not add irrelevant checklist states. Name meaningful omissions in the handoff.

## Forms and interaction

- Give form controls labels, useful defaults, validation, and submission feedback.
- Associate errors with controls and announce important status changes.
- Support the complete modeled flow with a keyboard; include arrow-key behavior where the control pattern requires it.
- Move focus deliberately after meaningful transitions.
- Give dialogs accessible names, contain focus, close on `Escape`, and restore focus to the trigger.
- Do not hide essential behavior behind hover.
- Keep touch targets usable and avoid accidental page-level horizontal overflow.

During browser verification, include `Tab`, `Shift+Tab`, `Enter`, `Space`, pattern-appropriate arrow keys, and `Escape` for dialogs. Inspect computed foreground and background colors on each distinct surface, especially inherited text inside dark or tinted regions.
