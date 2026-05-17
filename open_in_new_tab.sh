#!/usr/bin/env bash
# open_in_new_tab.sh <cmd>
# Open <cmd> in a new tab of the current terminal app — iTerm2 or macOS
# Terminal.app. Dispatches via $TERM_PROGRAM (iTerm sets "iTerm.app",
# Terminal.app sets "Apple_Terminal"). Unknown values fall back to iTerm.

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: open_in_new_tab.sh <cmd>" >&2
    exit 2
fi

cmd="$1"
esc=${cmd//\"/\\\"}

case "${TERM_PROGRAM:-}" in
    Apple_Terminal)
        osascript \
            -e 'tell application "Terminal" to activate' \
            -e 'tell application "System Events" to keystroke "t" using {command down}' \
            -e 'delay 0.3' \
            -e "tell application \"Terminal\" to do script \"$esc\" in selected tab of front window"
        ;;
    *)
        osascript \
            -e 'tell application "iTerm" to activate' \
            -e 'tell application "iTerm" to if (count of windows) = 0 then create window with default profile' \
            -e 'tell application "iTerm" to tell current window to create tab with default profile' \
            -e "tell application \"iTerm\" to tell current session of current window to write text \"$esc\""
        ;;
esac
