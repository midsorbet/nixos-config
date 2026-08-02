---
name: codex-connectors
description: Use ChatGPT/Codex connectors from OMP when the user explicitly asks to access a configured service such as Gmail, Google Calendar, Drive, GitHub, Linear, Outlook, or Contacts.
---

# Codex connectors

Access configured ChatGPT/Codex connectors directly through `cxporter`. Activate this workflow only when the user explicitly asks to use connector-backed data or actions. A general question about a service does not require connector access.

## Context boundary

Use the `cxporter` CLI through OMP's `bash` tool. Do not start `cxporter serve` for routine connector access: its MCP surface exports the full selected server catalog, which defeats on-demand discovery and adds every connector tool to the live tool set. `cxporter call` invokes the selected MCP tool directly; it does not start a Codex model turn.

## Workflow

1. Discover configured connectors when the target is not already clear:

   ```bash
   cxporter apps
   ```

   Add `--force` only when a newly configured connector is missing from the cached list.

2. Resolve the exact raw tool name. Never guess it:

   ```bash
   cxporter list --server codex_apps --connector "Google Calendar" --format text
   ```

   Use `--format json` when programmatic filtering is useful.

3. Read the current input schema before every unfamiliar call:

   ```bash
   cxporter schema codex_apps google_calendar.search_events
   ```

4. Call the raw tool with the smallest sufficient argument object:

   ```bash
   cxporter call codex_apps google_calendar.search_events '{"query":"example"}'
   ```

   For nested or quote-heavy arguments, write a temporary JSON file and pass `--args-file <path>` instead of building fragile shell quoting.

5. Check both the process exit status and the MCP result's `isError` field. Extract only the information needed for the request; do not echo unrelated private connector data.

## Outlook personal accounts

Microsoft Outlook Email's `search_messages` operation can reject a connected personal Microsoft account with `This API is not supported for MSA accounts (no addressUrl for Microsoft.MicrosoftSearch,False)`. This is a Microsoft Search account limitation, not evidence that connector authentication expired.

When that exact failure occurs:

1. Do not retry the same search or start an OAuth-refresh loop.
2. For recent or otherwise bounded mail requests, inspect the current schemas for `get_recent_emails` or `list_messages`, retrieve the smallest useful page, and filter only those returned fields locally.
3. Fetch full content only for the exact message IDs needed, using `fetch_message` or `fetch_messages_batch` after reading its current schema.
4. If a broad historical search cannot be answered from bounded list/fetch calls, explain the connector limitation. Use Outlook's visible signed-in UI through the `chatgpt-sky-computer-use` workflow only when the user requested that mailbox work and the current app state verifies the intended Outlook surface.

## Safety

- Use a mutating tool only when the user explicitly requested that specific side effect. Inspection or discovery is not authorization to create, send, update, delete, respond, merge, transition, archive, or label.
- Keep the default `--retry 0` for mutations. A read-only call may use `--retry 1` only after a concrete transient transport failure.
- Never use `--no-preflight`; fix arguments against the current schema instead.
- Never run `cxporter auth export --reveal` or print access tokens unless the user explicitly requests credential export. Do not implement a parallel OAuth flow.
- On a genuine authentication failure, preserve the error and direct the user to refresh the existing Codex/ChatGPT connector login. Do not misclassify the Outlook MSA search limitation above as authentication failure.
