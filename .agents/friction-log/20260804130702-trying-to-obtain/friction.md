---
title: 'Trying to obtain Bun 1.3.14 with `aube dlx bun@1.3.14` failed first because Node was absent and'
severity: 'minor'
---

Trying to obtain Bun 1.3.14 with `aube dlx bun@1.3.14` failed first because Node was absent and then because aube skipped Bun's required postinstall, leaving the bun.exe stub. For reproducible collab-web regeneration, use the Nix-provided Bun and compare an old-tag rebuild against the checked-in bundle before accepting the new build.

---
Migrated from PAPERCUTS.md; originally captured 2026-08-01T14:33:47-07:00 by `openai-codex/gpt-5.6-sol`.
