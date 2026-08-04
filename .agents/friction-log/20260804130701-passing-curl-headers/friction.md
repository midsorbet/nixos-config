---
title: 'Passing curl headers and JSON as separate ssh arguments caused the remote shell to strip'
severity: 'minor'
---

Passing curl headers and JSON as separate ssh arguments caused the remote shell to strip quoting, so curl misread JSON words as hosts. Wrapping the entire remote curl command in one quoted ssh command preserved the header and request body.

---
Migrated from PAPERCUTS.md; originally captured 2026-07-19T12:49:39-07:00 by `openai-codex/gpt-5.6-sol`.
