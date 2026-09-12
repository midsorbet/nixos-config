# `remindctl` workflows

Consult only the section needed for the current request. Current command help is authoritative if it differs from this reference.

## Inspect reminders and lists

`remindctl` defaults to `show today`.

- `show` accepts `today`, `tomorrow`, `week`, `overdue`, `upcoming`, `open`, `completed`, `all`, or a date string.
- `show --list <name>` limits a view to one named list. When policy provides a stable list ID, prefer `--list-id <id>`.
- `open` includes every incomplete reminder, including reminders without due dates.
- `list` with no arguments shows lists; `list <name...>` shows reminders from one or more named lists.
- `search` finds reminders by query. `info <id> --json` reads one reminder for post-mutation verification.
- `status` reports authorization without prompting.

Use `--json` when another step needs structured data. Aliases are `-j`, `--json-output`, and `--jsonOutput`. `--plain` emits stable tab-separated output; `--quiet` reduces output; `--no-color` disables color; `--no-input` disables interactive prompts.

JSON may include EventKit fields such as `creationDate`, `lastModifiedDate`, `url`, `alarmDate`, `locationTrigger`, and `recurrenceRule`. Display indexes and IDs come from read output, but never use a numeric index or an ID from an unscoped read when an applicable account-targeting policy requires a scoped full ID.

## Create

`add` accepts a title positionally or through `--title`, never both.

- `--list <name>` or `--list-id <id>` chooses the destination.
- `--due <date>` sets the due date.
- `--alarm <date>` overrides the alarm date.
- `--notes <text>` and `--url <url>` set notes and the dedicated URL field.
- `--repeat <rule>` sets recurrence.
- `--priority <none|low|medium|high>` sets priority.
- `--location <address>` creates a location trigger; `--radius <meters>` changes its geofence; `--leaving` changes arrival to departure. `--radius` and `--leaving` require `--location`.

Without a list target, EventKit uses the Reminders default list. Never assume that default has a particular name. If no default exists, provide a list target. An applicable local account-targeting policy can prohibit use of this generic default.

## Edit and move

`edit <id>` can set `--title`, `--list` or `--list-id`, `--notes`, `--priority`, and completion state. It also supports these paired operations:

- `--due` / `--clear-due`
- `--alarm` / `--clear-alarm`
- `--url` / `--clear-url`
- `--repeat` / `--no-repeat`
- `--complete` / `--incomplete`

Do not combine both sides of a pair. Move a reminder with `edit <id> --list <new-list>` or the policy-required list-ID form rather than deleting and recreating it. Due-only edits preserve alarms; explicit alarm edits preserve relative and location-based alarms.

## Dates and recurrence

Accepted date inputs include:

- `today`, `tomorrow`, `yesterday`
- `YYYY-MM-DD`
- `YYYY-MM-DD HH:mm`
- ISO 8601 with or without a timezone

Date-only values create all-day reminders; date-time values create timed reminders. A timed due reminder gets an alarm at its due time unless `--alarm` overrides it. If the user gives only a calendar date, do not invent a time.

Repeat values include `daily`, `weekly`, `biweekly`, `monthly`, `yearly`, and `every N days/weeks/months/years`.

## Complete and delete

`complete` and `delete` require one or more IDs or indexes. Prefer full IDs; applicable account-targeting policy may require them. Both commands support `--dry-run`. `delete` prompts unless `--force` or `--no-input` suppresses interaction; use `--force` only when destructive intent is established.

Aliases are `done` for `complete` and `rm` for `delete`.

## Manage lists

- `list <name> --create` creates a missing list.
- `list <name> --rename <new-name>` renames one list.
- `list <name> --delete` deletes one list and its reminders.
- `--force` skips destructive list-deletion confirmation.

Create, rename, and delete accept one list name. Confirm exact account/list targeting before list mutations; same-named lists may exist in different accounts.

## Permission diagnosis

- `status` never prompts.
- `authorize` requests access when state is `notDetermined`.
- When denied, direct the user to **System Settings → Privacy & Security → Reminders**.
- If the system prompt does not appear, the upstream workaround is:

  ```sh
  osascript -e 'tell application "Reminders" to get name of reminders'
  ```

- Over SSH, authorization must be granted on the Mac actually running `remindctl`.
- Use `remindctl doctor --for-agent` for diagnosis, not routine reads.
