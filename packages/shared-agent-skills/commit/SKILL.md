---
name: commit
description: "Create Git commits using Scoped Commits format when the user requests a commit or repository instructions grant commit authority."
---

# Create Scoped Commits

Commit only with explicit user authority or standing repository authority.
Caller-provided paths and globs are hard boundaries; preserve unrelated worktree
changes. Never bypass hooks, amend, or expand scope without explicit permission.
Review staged content for secrets, credentials, debug artifacts, and unrelated
churn. Do not invoke `git push` directly.

In `/Users/me/vault/projects/<name>`, the configured post-commit hook may
commit the vault gitlink and push the project branch when
`/Users/me/vault/AGENTS.md` conditions pass. Do not duplicate that pointer
commit or promise that the project commit cannot push.

## Subject

Normal commits use `<scope>: <summary>`, or
`<scope>: <subscope>: <summary>` when an established hierarchy improves
scanning. Merge, revert, and other Git-generated commits may keep their standard
format.

- Follow repository instructions first. Reuse an accurate repository scope;
  inspect recent subjects with `git log -n 50 --pretty=format:%s` when history
  is needed. Otherwise infer a short lowercase area from the changed paths and
  domain.
- Scope names the affected subsystem, not a change kind: do not substitute
  `feat`, `fix`, `chore`, or `refactor`. Ticket numbers belong in the body or
  trailers.
- Use a lowercase imperative summary describing the observable result, with no
  final period. Keep the full subject at 72 characters or fewer unless the
  repository requires another convention.
- Split unrelated scopes into atomic commits. Keep implementation, tests, and
  directly related documentation together. For an irreducibly cross-cutting
  change, use an established parent/tree-wide scope or a concise comma-separated
  scope.

Examples: `auth: prevent expired sessions from refreshing`;
`terminal: osc: handle malformed color requests`.

## Body and trailers

Omit an unnecessary body. When useful, explain why and the behavioral change,
not an implementation diary; wrap prose near 72 characters. Add issue references
or trailers only when their relationship is known. Never add assistant
attribution or generated-by text. Do not add Conventional Commits
breaking-change markers solely for release automation; explain compatibility
impact in normal prose when it matters.

## Commit

Inspect `git status`, `git diff`, and `git diff --cached` to determine the
authorized boundary. Stop if there is nothing to commit. If file or hunk
ownership is ambiguous, ask the user. Stage only intended files or hunks and
review `git diff --cached` before running
`git commit -m "<scope>: <summary>"` (with a second `-m` when a body is useful).
Confirm the commit was recorded and report its subject.
