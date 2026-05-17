#!/usr/bin/env bash
# Alternative to parse_quicksel.sh — instead of parsing quicksel.vim, accept
# a plain "description<TAB>cmd" list, fzf-pick one, and run the cmd in a new
# tab of the current terminal (iTerm2 or Terminal.app — see open_in_new_tab.sh).
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

# $SCRIPTDIR is exported by common.sh; fall back to this script's directory when
# quicksel_list.sh is invoked standalone.
: "${SCRIPTDIR:=$( dirname -- "${BASH_SOURCE[0]}" )}"

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

"$SCRIPTDIR/open_in_new_tab.sh" "$cmd"
