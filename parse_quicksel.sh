#!/usr/bin/env bash
# Parse quicksel.vim into "name: command" lines, fzf-pick one, run it in iTerm
# (matching the original osascript behavior).

set -euo pipefail

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

# escape double-quotes for embedding in the AppleScript string
esc=${cmd//\"/\\\"}

osascript \
    -e 'tell application "iTerm" to activate' \
    -e 'tell application "iTerm" to if (count of windows) = 0 then create window with default profile' \
    -e 'tell application "iTerm" to tell current window to create tab with default profile' \
    -e "tell application \"iTerm\" to tell current session of current window to write text \"$esc\""
