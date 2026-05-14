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

osascript <<EOF
tell application "iTerm2"
    activate
    repeat with w in windows
        if (id of w) is $wid then
            select w
            tell w
                select tab $tidx
            end tell
            exit repeat
        end if
    end repeat
end tell
EOF
