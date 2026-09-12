---
name: apple-reminders
description: "Use remindctl when the user asks to inspect or change Apple Reminders on macOS, including lists, due dates, alarms, recurrence, completion, deletion, permission status, or location triggers."
homepage: https://github.com/openclaw/remindctl
---

# Apple Reminders

Use `remindctl` on macOS 14+. It works through EventKit, so changes follow the normal Reminders/iCloud sync path.

## Preconditions

- Have `remindctl` on `PATH` (install with `brew install steipete/tap/remindctl`) and grant Reminders access to the terminal app that runs it.
- If access is unknown, check it without prompting with `remindctl status`. Use `remindctl authorize` only when access is `notDetermined` and the user wants to proceed.
- Read the current list or reminder before changing it. Resolve mutations to an unambiguous full reminder ID; clarify an ambiguous title, list, or date rather than guessing.
- Treat reminder and list deletion as destructive. Require clear user intent, use `--dry-run` when scope is uncertain, and use `--force` only for an intentionally destructive request.
- For work in `/Users/me/vault`, follow the canonical Reminders account targeting, full-ID resolution, mutation, and verification policy in `/Users/me/vault/AGENTS.md`. Fail closed when its required iCloud list ID is absent. That policy overrides generic defaults and examples.
- Verify every mutation by reading the resulting reminder or confirming the deleted full ID is absent. Do not infer success from command exit alone.
- Do not put secrets or sensitive raw documents in Reminders.

## Workflows

Read [references/remindctl.md](references/remindctl.md) only for the relevant workflow:

- **Inspect reminders or authorization:** views, list filters, IDs, structured output, and permission handling.
- **Create or edit:** title/list targeting, dates, alarms, recurrence, priority, URLs, notes, locations, and moves.
- **Complete or delete:** full-ID targeting, dry runs, confirmations, and list deletion.
- **Diagnose access:** denied permissions, SSH targeting, or a missing system prompt.

Use Reminders for tasks, chores, follow-ups, and items that should resurface. Use a calendar instead for genuine appointments, meetings, travel windows, or other fixed events unless the user explicitly asks otherwise. `remindctl` does not support native sections, tags, smart lists, attachments, or Apple’s private Urgent toggle.
