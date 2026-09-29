#!/usr/bin/env bash
# pr-worktree.sh <pr-number> [worktree-dir]
# Create a worktree, `gh pr checkout` the PR in it, print the commit the PR
# branches off (merge-base with its base branch) and copy "DiffviewOpen <base>"
# to the clipboard, ready to paste into nvim opened inside the worktree.
set -euo pipefail
pr=${1:?usage: pr-worktree.sh <pr-number> [worktree-dir]}
root=$(git rev-parse --show-toplevel)
dir=${2:-$root/.claude/worktrees/pr$pr}

read -r head base < <(gh pr view "$pr" --json headRefOid,baseRefName --jq '"\(.headRefOid) \(.baseRefName)"')
git fetch -q origin "$base" "pull/$pr/head"

if [ ! -d "$dir" ]; then
  git worktree add --detach "$dir" "$head"
fi
(cd "$dir" && gh pr checkout "$pr")

mb=$(git merge-base "origin/$base" "$head")
echo "worktree:      $dir"
echo "PR head:       $(git log --oneline -1 "$head")"
echo "commit before: $(git log --oneline -1 "$mb")"
printf 'DiffviewOpen %s' "$mb" | pbcopy
echo "clipboard:     DiffviewOpen $mb"
