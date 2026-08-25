#!/usr/bin/env bash
# $EDITOR wrapper for Claude Code's Ctrl-G (open prompt in editor).
# Opens the file in an already-running nvim via neovim-remote and BLOCKS
# (--remote-wait) until the buffer is wiped, so Claude reads back the edits.
#
# Server selection:
#   1. servername in ~/temp/listen.txt (written by vimsettings.vim), if live
#   2. else the most-recent live nvim socket from `nvr --serverlist`
#   3. else launch a fresh nvim in Claude's terminal
set -uo pipefail

live_servers() { nvr --serverlist 2>/dev/null; }

pick_server() {
    local want="" ; [ -r "$HOME/temp/listen.txt" ] && want="$(cat "$HOME/temp/listen.txt")"
    local list; list="$(live_servers)"
    if [ -n "$want" ] && printf '%s\n' "$list" | grep -qxF "$want"; then
        printf '%s' "$want"; return 0
    fi
    # Fall back to the last-listed nvim UNIX socket (…/nvim.<pid>.0).
    printf '%s\n' "$list" | grep -E '/nvim\.[0-9]+\.[0-9]+$' | tail -n1
}

server="$(pick_server)"

if [ -n "$server" ]; then
    # bufhidden=wipe so closing the window (:q / :wq) wipes the buffer, which
    # is what releases --remote-wait and returns the edits to Claude.
    exec nvr --servername "$server" --remote-wait +'setlocal bufhidden=wipe' "$@"
else
    exec nvim "$@"
fi
