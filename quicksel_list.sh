#!/usr/bin/env bash
# Alternative to parse_quicksel.sh — instead of parsing quicksel.vim, accept
# a plain "description<TAB>cmd" list, fzf-pick one, and run the cmd in iTerm.
#
# Input precedence:
#   1. Argument "-"           — read list from stdin
#   2. First positional arg   — path to a tsv file
#   3. $QUICKSEL_LIST_FILE    — env-configured path
#   4. ~/temp/quicksel_list.tsv (default)
#
# List format: one entry per line, description and command separated by a TAB.
# Blank lines and lines starting with `#` are ignored.
#
# Examples:
#   quicksel_list.sh                                   # read default file
#   quicksel_list.sh ~/my-commands.tsv                 # read specified file
#   printf 'build\tmake\ntest\tpytest\n' | quicksel_list.sh -

set -euo pipefail

read_input() {
    if [[ "${1:-}" == "-" ]]; then
        cat
    else
        local file="${1:-${QUICKSEL_LIST_FILE:-$HOME/temp/quicksel_list.tsv}}"
        [[ -f "$file" ]] || { echo "no file: $file" >&2; exit 1; }
        cat "$file"
    fi
}

# Strip comments/blank lines, keep only well-formed description<TAB>cmd rows.
entries=$(read_input "${1:-}" | awk -F'\t' '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    NF >= 2 { print }
')

[[ -n "$entries" ]] || { echo "no entries" >&2; exit 1; }

sel=$(printf '%s\n' "$entries" \
    | fzf --with-nth=1 --delimiter=$'\t' \
          --preview 'echo {2}' --preview-window=down:3:wrap) || exit 0

cmd=${sel#*$'\t'}
esc=${cmd//\"/\\\"}

osascript \
    -e 'tell application "iTerm" to activate' \
    -e 'tell application "iTerm" to if (count of windows) = 0 then create window with default profile' \
    -e 'tell application "iTerm" to tell current window to create tab with default profile' \
    -e "tell application \"iTerm\" to tell current session of current window to write text \"$esc\""
