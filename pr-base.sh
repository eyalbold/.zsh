#!/usr/bin/env bash
# pr-base.sh [--range] [<pr-number>]
# Print (only) the commit a PR branches off: the merge-base of its head with
# its base branch. No argument -> the PR of the current branch.
# --range prints <merge-base>..<pr-head>, so the diff's other side is the PR's
# own head rather than whatever the local worktree happens to hold.
set -euo pipefail
range=0
if [[ ${1:-} == --range ]]; then range=1; shift; fi
pr=${1:-}
pr=${pr#\#}

read -r num head base < <(gh pr view ${pr:+"$pr"} --json number,headRefOid,baseRefName \
    --jq '"\(.number) \(.headRefOid) \(.baseRefName)"')
git fetch -q origin "$base" "pull/$num/head"
mb=$(git merge-base "origin/$base" "$head")
if (( range )); then echo "$mb..$head"; else echo "$mb"; fi
