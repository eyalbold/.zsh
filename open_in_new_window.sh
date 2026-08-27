#!/usr/bin/env bash
# open_in_new_window.sh <cmd>
# Open <cmd> in a new WINDOW of the current terminal app — iTerm2 or macOS
# Terminal.app. Same dispatch as open_in_new_tab.sh (via $TERM_PROGRAM), but a
# window rather than a tab, and it prints the new window's id on stdout so the
# caller can close it when the command is done.

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: open_in_new_window.sh <cmd>" >&2
    exit 2
fi

cmd="$1"
# AppleScript string escaping: backslash first, then double quote. See the same
# note in open_in_new_tab.sh — an unescaped backslash breaks the osascript parse.
esc=${cmd//\\/\\\\}
esc=${esc//\"/\\\"}

case "${TERM_PROGRAM:-}" in
    Apple_Terminal)
        # `do script` with no `in` clause opens a new window and returns its tab.
        osascript \
            -e 'tell application "Terminal" to activate' \
            -e "tell application \"Terminal\" to do script \"$esc\"" \
            -e 'tell application "Terminal" to return id of front window as text'
        ;;
    *)
        osascript \
            -e 'tell application "iTerm" to activate' \
            -e "tell application \"iTerm\"
                    set w to (create window with default profile)
                    tell current session of w to write text \"$esc\"
                    return id of w as text
                end tell"
        ;;
esac
