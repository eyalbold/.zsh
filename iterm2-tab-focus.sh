#!/usr/bin/env bash
# Pick an iTerm2 tab via fzf and focus it.

set -euo pipefail

lines=$(osascript <<'EOF'
set SEP to "|"
tell application "iTerm2"
    set output to ""
    set winIndex to 0
    repeat with w in windows
        set winIndex to winIndex + 1
        set wid to id of w
        set tabIndex to 0
        repeat with t in tabs of w
            set tabIndex to tabIndex + 1
            set sess to current session of t
            set sname to name of sess
            set cwd to ""
            try
                tell sess
                    set cwd to (variable named "session.path")
                end tell
            end try
            set label to "[W" & winIndex & ".T" & tabIndex & "] " & sname
            if cwd is not "" then
                set label to label & "  —  " & cwd
            end if
            set output to output & wid & SEP & tabIndex & SEP & label & linefeed
        end repeat
    end repeat
    return output
end tell
EOF
)

selected=$(printf '%s' "$lines" \
    | fzf --with-nth=3.. \
          --delimiter='\|' \
          --prompt="iTerm2 tab> " \
          --height=80% \
          --reverse)

[ -z "$selected" ] && exit 0

wid=${selected%%|*}
rest=${selected#*|}
tidx=${rest%%|*}

# Focus order matters on multi-monitor setups: select the target window + tab
# FIRST (so iTerm's current window/tab is correct), activate the app, and only
# then raise the SPECIFIC window via System Events. `activate` alone brings
# forward whichever window is frontmost on the current Space/display — on a
# second monitor that's the wrong one. AXRaise targets the exact window.
#
# The join key is the window's top-left corner: iTerm's `bounds` top-left equals
# System Events' `position` exactly, and (unlike the window title, which is often
# duplicated) it is unique. wid/tidx are passed as argv, not interpolated.
osascript - "$wid" "$tidx" <<'EOF'
on run argv
    set targetId to (item 1 of argv) as integer
    set targetTab to (item 2 of argv) as integer
    set tx to missing value
    set ty to missing value
    tell application "iTerm2"
        try
            set w to window id targetId
        on error
            return
        end try
        tell w
            select
            select tab targetTab
        end tell
        set b to bounds of w
        set tx to item 1 of b
        set ty to item 2 of b
        activate
    end tell
    if tx is missing value then return
    tell application "System Events" to tell process "iTerm2"
        set frontmost to true
        try
            perform action "AXRaise" of (first window whose position is {tx, ty})
        end try
    end tell
end run
EOF
