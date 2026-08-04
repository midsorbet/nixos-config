---
title: 'On a fresh Herdr pane, `herdr pane read --source recent-unwrapped` returned empty even after'
severity: 'minor'
---

On a fresh Herdr pane, `herdr pane read --source recent-unwrapped` returned empty even after commands had produced output, while `--source visible --raw` showed it correctly. Fresh-pane automation should fall back to `visible` or Herdr should populate recent history consistently.

---
Migrated from PAPERCUTS.md; originally captured 2026-07-28T07:16:44-07:00 by `openai-codex/gpt-5.6-sol`.
