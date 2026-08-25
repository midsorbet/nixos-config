---
name: commit
description: "Create Git commits using Scoped Commits format"
---

# Create Scoped Commits

Create Git commits only when the user explicitly requests a commit. Use
scope-first subjects so the log shows where each change belongs before it
describes what changed.

## Format

Use this format for normal commits:

`<scope>: <summary>`

Examples:

`auth: prevent expired sessions from refreshing`

`terminal/osc: handle malformed color requests`

`projects: update nixos-config pointer`

Merge commits, revert commits, and other Git-generated special commits MAY keep
their established format.

## Scope

- Scope is REQUIRED for normal commits. It identifies the subsystem, area,
  module, package, or other project-specific subject of the change.
- Follow repository instructions first. Then inspect recent subjects with
  `git log -n 50 --pretty=format:%s` and reuse an established scope when it
  accurately describes the change.
- When history does not provide a scope, infer a short, lowercase scope from
  the changed paths and the domain they implement.
- Use nested scopes such as `terminal/osc` when the narrower area is useful
  and unambiguous.
- Do not substitute change-kind labels such as `feat`, `fix`, `chore`, or
  `refactor` for the affected area. A label such as `build`, `docs`, or
  `tests` is valid only when it is the actual project area.
- A ticket number is not a scope. Put it in the body or an appropriate trailer.
- Split unrelated scopes into separate commits. For one irreducibly
  cross-cutting change, prefer a shared parent scope. If none exists, use a
  concise comma-separated scope or an established tree-wide scope.

## Summary

- Start with a lowercase imperative verb unless the repository convention
  requires different capitalization.
- Describe the observable result, not the implementation process.
- Keep the complete subject line at 72 characters or fewer.
- Do not add a redundant type before the scope.
- Do not end the subject with a period.

## Body and trailers

- The body is OPTIONAL. Omit it when the subject explains an obvious change.
- When useful, explain why the change is needed, the important previous
  behavior, and the new behavior at a high level. Do not write an implementation
  diary or restate the diff.
- Use short paragraphs and wrap prose at approximately 72 characters.
- Add issue references or trailers only when the relationship is known from the
  user request, repository context, branch, or diff.
- Do not add assistant attribution, sign-offs, or generated-by text.
- Do not add Conventional Commits breaking-change markers solely for release
  automation. Explain compatibility impact in normal prose when it matters.

## Commit boundaries

- Keep each commit atomic around one logical change.
- Keep implementation, tests, and directly related documentation together.
- Split unrelated work, but do not split one coherent change merely because its
  parts would have different Conventional Commits types.
- Preserve unrelated existing worktree changes.

## Safety

- Treat caller-provided paths or globs as hard commit boundaries. Stage and
  commit only those paths unless the user explicitly expands the request.
- If it is unclear whether a file or hunk belongs in the commit, ask the user.
- Review staged content before committing. Do not commit secrets, credentials,
  debug artifacts, or unrelated formatting churn.
- Never bypass commit hooks unless the user explicitly requests it.
- Do not amend an existing commit unless the user explicitly requests it.
- Do not invoke `git push` directly.

In `/Users/me/vault/projects/<name>`, the configured post-commit hook
automatically commits the vault gitlink and may push the project branch when the
conditions in `/Users/me/vault/AGENTS.md` pass. Do not create a duplicate
pointer commit or promise that the project commit cannot push.

## Workflow

1. Infer any requested files, globs, and commit guidance from the prompt.
2. Review `git status`, `git diff`, and `git diff --cached` to understand
   both staged and unstaged changes. Stop if there is nothing to commit.
3. Choose the logical commit boundary and scope from repository instructions,
   recent history, changed paths, and the affected domain.
4. Stage only the intended files or hunks, then review `git diff --cached`.
5. Run `git commit -m "<scope>: <summary>"`. Add a second `-m` argument only
   when a body is useful.
6. Confirm the commit was recorded and report its subject. Do not push directly.
