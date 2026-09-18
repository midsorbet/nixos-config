#!/bin/sh
set -u

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
local_env_vars=$(git rev-parse --local-env-vars 2>/dev/null) || exit 0

# Hooks inherit repository-local Git environment. Clear it before every
# independent command explicitly targeted at the committed repository.
for env_name in $local_env_vars; do
  unset "$env_name"
done

project_name=$(basename "$repo_root")
branch=$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null) || {
  echo "project hook: skipped push for $project_name because HEAD is detached" >&2
  exit 0
}

upstream=$(git -C "$repo_root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || {
  echo "project hook: skipped push for $project_name because $branch has no upstream" >&2
  exit 0
}

remote=$(git -C "$repo_root" for-each-ref --format='%(upstream:remotename)' "refs/heads/$branch" 2>/dev/null) || {
  echo "project hook: skipped push for $project_name because upstream '$upstream' has no remote" >&2
  exit 0
}
merge_ref=$(git -C "$repo_root" for-each-ref --format='%(upstream:remoteref)' "refs/heads/$branch" 2>/dev/null) || {
  echo "project hook: skipped push for $project_name because upstream '$upstream' has no branch ref" >&2
  exit 0
}

case $merge_ref in
  refs/heads/?*) remote_branch=${merge_ref#refs/heads/} ;;
  *)
    echo "project hook: skipped push for $project_name because upstream '$upstream' is not a remote branch" >&2
    exit 0
    ;;
esac

if [ -z "$remote" ] || [ "$remote" = "." ]; then
  echo "project hook: skipped push for $project_name because upstream '$upstream' is not a remote branch" >&2
  exit 0
fi

status=$(git -C "$repo_root" status --porcelain) || {
  echo "project hook: skipped push for $project_name because worktree status could not be read" >&2
  exit 0
}
if [ -n "$status" ]; then
  echo "project hook: skipped push for $project_name because the worktree is dirty" >&2
  exit 0
fi

ahead_behind=$(git -C "$repo_root" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null) || {
  echo "project hook: skipped push for $project_name because upstream '$upstream' could not be compared" >&2
  exit 0
}
set -- $ahead_behind
behind=$1
ahead=$2

if [ "$behind" != "0" ]; then
  echo "project hook: skipped push for $project_name because $branch is behind $upstream" >&2
  exit 0
fi

[ "$ahead" != "0" ] || exit 0

if git -C "$repo_root" push -- "$remote" "HEAD:$remote_branch"; then
  echo "project hook: pushed $project_name $branch to $upstream" >&2
else
  echo "project hook: failed to push $project_name $branch to $upstream" >&2
fi

exit 0
