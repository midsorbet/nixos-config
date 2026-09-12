---
name: librarian
description: "Cache and refresh remote Git repositories under ~/.cache/checkouts/<host>/<org>/<repo> for later local reference. Invoke when a user points to, or the task encounters, a remote repository URL or owner/repo reference."
---

# Librarian

Use this skill to resolve a reusable local checkout for a remote repository,
not to edit the shared cache. Accepted references include GitHub, GitLab, and
Bitbucket URLs, `git@...` URLs, and `owner/repo` shorthand (which defaults to
`github.com`). The canonical path is
`~/.cache/checkouts/<host>/<org>/<repo>`; `LIBRARIAN_CACHE_ROOT` may override
that root.

Run the bundled command from this skill directory:

```bash
bash checkout.sh <repo> --path-only
```

Examples:

```bash
bash checkout.sh mitsuhiko/minijinja --path-only
bash checkout.sh github.com/mitsuhiko/minijinja --path-only
bash checkout.sh https://github.com/mitsuhiko/minijinja --path-only
```

The command parses the reference, uses a partial clone with
`--filter=blob:none` when creating a checkout, reuses an existing one, and
refreshes stale checkouts. Refresh is throttled to 300 seconds by default; set
`LIBRARIAN_UPDATE_INTERVAL` or force it with:

```bash
bash checkout.sh <repo> --force-update --path-only
```

When an existing checkout is clean and has an upstream, refresh may fast-forward
it. Use the returned path for searching, reading, and analysis. For edits,
create a separate worktree or copy. Re-run `checkout.sh` for later references so
the cached checkout can refresh.
