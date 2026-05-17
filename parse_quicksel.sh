#!/usr/bin/env bash
# Parse quicksel.vim into "name: command" lines, fzf-pick one, run it in a new
# tab of the current terminal (iTerm2 or Terminal.app — see open_in_new_tab.sh).

set -euo pipefail

# $SCRIPTDIR is exported by common.sh; fall back to this script's directory when
# parse_quicksel.sh is invoked standalone.
: "${SCRIPTDIR:=$( dirname -- "${BASH_SOURCE[0]}" )}"

file="${QUICKSEL_FILE:-$HOME/temp/quicksel.vim}"
[[ -f "$file" ]] || { echo "no file: $file" >&2; exit 1; }

parse() {
    local fn="" line cmd
    while IFS= read -r line; do
        case "$line" in
            function!*|"function "*)
                fn=$(printf '%s\n' "$line" | sed -E 's/^function!?[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/')
                ;;
            *"write text"*)
                [[ -z "$fn" ]] && continue
                cmd=$(printf '%s\n' "$line" | sed -E 's/.*write text "([^"]*)".*/\1/')
                printf '%s\t%s\n' "$fn" "$cmd"
                fn=""
                ;;
        esac
    done < "$file"
}

# --list mode just prints the parsed table
if [[ "${1:-}" == "--list" ]]; then
    parse | column -t -s $'\t'
    exit 0
fi

sel=$(parse | fzf --with-nth=1 --delimiter=$'\t' --preview 'echo {2}' --preview-window=down:3:wrap) || exit 0
cmd=${sel#*$'\t'}

"$SCRIPTDIR/open_in_new_tab.sh" "$cmd"
