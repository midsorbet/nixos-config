---
name: codex-connectors
description: Use configured ChatGPT/Codex connectors only when the user explicitly asks to access Gmail, Google Calendar, Drive, GitHub, Linear, Outlook, Contacts, or another connector-backed service.
---

# Codex connectors

Use `cxporter` through OMP's `bash` tool for explicitly requested
connector-backed data or actions. A general question about a service does not
invoke this skill. Do not start `cxporter serve`: it exposes the full server
catalog. `cxporter call` invokes one raw MCP tool without starting a Codex
model turn.

## Discover and call

Discover only what the request needs:

```bash
cxporter apps
cxporter list --server codex_apps --connector "Google Calendar" --format text
cxporter schema codex_apps google_calendar.search_events
cxporter call codex_apps google_calendar.search_events '{"query":"example"}'
```

Use `cxporter apps --force` only when a newly configured connector is absent
from cache. Never guess raw tool names or unfamiliar inputs; read the current
schema. Use `--format json` for programmatic discovery and
`--args-file <path>` for nested or quote-heavy arguments. Check both process
status and the MCP result's `isError` field. Return only requested information,
not unrelated private connector data.

For the personal Microsoft-account limitation in Outlook search, read
[Outlook personal accounts](references/outlook-personal.md).

## Authorization and credentials

- A mutating call requires the user's explicit request for that exact side
  effect. Read/discovery access does not authorize creating, sending, updating,
  deleting, responding, merging, transitioning, archiving, or labeling.
- Keep `--retry 0` for mutations. A read-only call may use `--retry 1` only
  after a concrete transient transport failure.
- Never use `--no-preflight`; correct arguments against the current schema.
- Never run `cxporter auth export --reveal` or print access tokens unless the
  user explicitly requests credential export. Do not create a parallel OAuth
  flow.
- On genuine authentication failure, preserve the error and direct the user to
  refresh the existing Codex/ChatGPT connector login.
