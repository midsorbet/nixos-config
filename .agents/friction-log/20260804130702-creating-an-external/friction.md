---
title: 'Creating an external linked worktree from this vault submodule inherited the common repository''s'
severity: 'minor'
---

Creating an external linked worktree from this vault submodule inherited the common repository's relative core.worktree, so git status misreported the linked tree as mass deletions. Set a worktree-local absolute root with `git config --worktree core.worktree &lt;linked-path&gt;` immediately after `git worktree add`.

---
Migrated from PAPERCUTS.md; originally captured 2026-08-01T08:59:33-07:00 by `openai-codex/gpt-5.6-sol`.
