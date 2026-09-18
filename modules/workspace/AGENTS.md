# Project Workspace Instructions

Each direct child of `@PROJECTS_ROOT@` is an independent source repository.
Enter the intended repository before running Git, Nix, package-manager, test, or
project commands, then read and follow its repository-local `AGENTS.md` and
maintained documentation.

- The repository-local instructions, issue tracker or maintained task system,
  Git history, and maintained documentation are canonical for project context,
  decisions, resume state, and operational open loops.
- Keep code, tests, generated artifacts, and thread-local resume context in the
  owning repository. Do not create sibling project journals or copy issue state
  into this workspace.
- Personal and cross-project context belongs in the sibling vault at
  `@PROJECTS_ROOT@/vault`. Read its `AGENTS.md` at
  `@PROJECTS_ROOT@/vault/AGENTS.md` when that context is relevant, but do not
  treat the vault as the owner of repository-local state.
- Preserve unrelated working-tree changes and published history. Use atomic
  Scoped Commit messages in the form `<scope>: <summary>`; standing authority
  is granted to create appropriate commits for completed repository work unless
  the current request or repository-local policy says otherwise.
- Standing approval permits the configured post-commit hook to publish a new
  commit automatically only when HEAD is on an attached branch, its upstream is
  a valid remote branch, the worktree is clean, the upstream and HEAD can be
  compared, the local branch is not behind, and it is ahead. Repository-local
  instructions and the current request may narrow or disable that authority.
- Never force-push or create pointer commits merely to trigger publication.
  Automatic post-commit publication does not relax repository privacy or
  remote-content rules and does not authorize unrelated manual or bulk
  repository mutations. Back up the vault independently under its own policy.
- The workspace catalog is for discovery and read-only context/status queries.
  It is not a lockfile, task database, mutation grant, or source of remote and
  revision truth.

These instructions are agent-neutral. Model-specific behavior and global tool
policy belong in their declaratively managed configuration, not here.
