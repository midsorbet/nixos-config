# Outlook personal accounts

Read this only after Microsoft Outlook Email `search_messages` fails for a
connected personal Microsoft account with:

`This API is not supported for MSA accounts (no addressUrl for Microsoft.MicrosoftSearch,False)`

This is a Microsoft Search account limitation, not proof that connector
authentication expired.

- Do not retry the same search or begin OAuth refresh.
- For recent or bounded mail, inspect the current schema for
  `get_recent_emails` or `list_messages`, request the smallest useful page,
  and filter only returned fields locally.
- Fetch full content only for the exact required message IDs with
  `fetch_message` or `fetch_messages_batch` after reading its current schema.
- If bounded list/fetch calls cannot answer a broad historical search, explain
  the limitation. Use Outlook's visible signed-in UI only when the user requested
  work in that mailbox and the current `cua-computer-use` app policy explicitly
  allows Outlook's bundle ID and verifies the intended surface.
