# common.sh — shared shell setup sourced by ~/.bashrc and ~/.zshrc.
# Provides aliases, keybindings, and helper functions for the interactive shell.

# -- Locate this script's directory ------------------------------------------
# Needed so functions below can find sibling scripts (parse_quicksel.sh, etc.)
# regardless of which shell sourced this file or from where.
if [ -n "$BASH_VERSION" ]; then
    SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [ -n "$ZSH_VERSION" ]; then
    SCRIPT_PATH="${(%):-%x}"
else
    # sh/dash fallback — only correct if the script is executed, not sourced.
    SCRIPT_PATH="$0"
fi
SCRIPTDIR="$( dirname -- "$SCRIPT_PATH" )"
export SCRIPTDIR

# -- Optional user config -----------------------------------------------------
[ -f "$SCRIPTDIR/config.sh" ] && . "$SCRIPTDIR/config.sh"

# -- Aliases ------------------------------------------------------------------
# cl: shortcut for the sandboxed Claude Code wrapper.
# cc: same wrapper but resumes the most recent session.
alias cl=claude
alias cc='claude --continue'

# -- Keybindings (emacs-mode in zsh) -----------------------------------------
# Disabled by default. To enable, set SCRIPTS_KEYBINDINGS=1 in config.sh.
# bindkey is zsh-only, so skip the whole block under bash.
if [ "${SCRIPTS_KEYBINDINGS:-0}" = "1" ] && [ -n "$ZSH_VERSION" ]; then
    bindkey -e
    bindkey '\e\e[C' forward-word
    bindkey '\e\e[D' backward-word
    bindkey -s '^X' 'QuickSelList\n'    # fuzzy-pick a command from quicksel.vim
    bindkey -s '^E' 'ClaudeZi\n'    # fuzzy search recent folders (using zoxide), open claude there
    bindkey -s '^Y' 'TabFocus\n'    # focus a specific iTerm tab
    bindkey -s '^Q' 'zi\n'          # interactive zoxide
fi

function EnableShortcuts()
{
    echo 'export SCRIPTS_KEYBINDINGS=1' >> "$SCRIPTDIR/config.sh"
}



# ClaudeZiStrong: fuzzy search recent folders (using zoxide), then open a new
# terminal tab running `claude` (the unsandboxed CLI) in that directory.
function ClaudeZiStrong() {
    local dir
    dir=$(zoxide query -l | fzf --preview 'ls -la {}' --preview-window=right:50%:wrap) || return 0
    "$SCRIPTDIR/open_in_new_tab.sh" "cd ${(q)dir} && claude"
}

# ClaudeZi: fuzzy search recent folders (using zoxide), then open a new
# terminal tab running the sandboxed `claude` wrapper in that dir.
# This is the default Claude launcher and is bound to ^B.
function ClaudeZi() {
    local dir
    dir=$(zoxide query -l | fzf --preview 'ls -la {}' --preview-window=right:50%:wrap) || return 0
    "$SCRIPTDIR/open_in_new_tab.sh" "cd ${(q)dir} && claude"
}

# SudoRun: run a command with sudo in a NEW terminal tab, so the password prompt
# is interactive. Useful when the caller has no TTY for sudo to prompt on — an
# agent, a hook, a piped script — where `sudo -n` just fails with
# "a password is required".
#
#   SudoRun launchctl bootstrap system /Library/LaunchDaemons/foo.plist
#   SudoRun "cp a.plist /Library/LaunchDaemons/ && launchctl bootstrap system /Library/LaunchDaemons/a.plist"
#
# The command's combined stdout+stderr is tee'd to a log file, so it stays
# visible in the tab AND is readable by the caller. SudoRun BLOCKS until the
# command finishes, then prints that output on its own stdout and exits with the
# command's status — so an agent that can't type the root password still gets the
# result. sudo prompts on /dev/tty, so the password prompt is unaffected by the pipe.
#
# The new tab stays open afterwards so output remains on screen; close it yourself.
#
# Env:
#   SUDORUN_TIMEOUT   seconds to wait for completion (default 300); on timeout
#                     returns 124 after dumping whatever was logged so far.
#   SUDORUN_LOG_DIR   log directory (default ${TMPDIR:-/tmp}/sudorun)
function SudoRun() {
    if [ $# -eq 0 ]; then
        echo "usage: SudoRun <command...>" >&2
        return 2
    fi
    local cmd
    if [ $# -eq 1 ]; then
        # Single argument: already a full command line, pass through verbatim so
        # shell operators (&&, |, redirection) keep working.
        cmd="$1"
    else
        # Multiple arguments: quote each so paths with spaces survive.
        cmd="${(j: :)${(q)@}}"
    fi

    local logdir=${SUDORUN_LOG_DIR:-${TMPDIR:-/tmp}/sudorun}
    mkdir -p "$logdir" || return 1
    # root executes $cmdfile out of this dir, so make sure nobody else can write
    # into it (matters only if it lands in a shared /tmp rather than a per-user
    # TMPDIR). Bail rather than hand root a file someone else may control.
    chmod 700 "$logdir" 2>/dev/null
    if [ ! -O "$logdir" ]; then
        echo "SudoRun: $logdir is not owned by you — refusing to run" >&2
        return 1
    fi
    local stamp="$(date +%Y%m%d-%H%M%S)-$$"
    local log="$logdir/$stamp.log"
    local rcfile="$logdir/$stamp.rc"
    local cmdfile="$logdir/$stamp.cmd"

    # Stash the command in a script rather than interpolating it into the string
    # we hand to AppleScript: it survives arbitrary quotes/backslashes untouched,
    # and `sudo zsh <file>` runs the WHOLE command line as root. (Interpolating
    # `sudo $cmd` instead would apply sudo only to the first command, since `&&`
    # binds looser — `sudo a && b` runs b as the calling user.)
    print -r -- "$cmd" > "$cmdfile" || return 1

    # Show what actually gets run as root. In the multi-arg form this is the
    # re-quoted line, not the argv the caller typed, so it is worth seeing.
    # stderr, because stdout carries the command's own output.
    echo "SudoRun: running as root: $cmd" >&2

    # In the new tab: tee the combined output, then record the command's own exit
    # status. `\${pipestatus[1]}` is escaped so the tab's shell evaluates it, and
    # it is sudo's status rather than tee's. `sudo zsh …` is a single simple
    # command, so the pipe captures all of it. Writing $rcfile last doubles as the
    # completion marker — by then tee has flushed $log.
    if ! "$SCRIPTDIR/open_in_new_tab.sh" \
        "cd ${(q)PWD} && sudo zsh ${(q)cmdfile} 2>&1 | tee ${(q)log}; print -r -- \${pipestatus[1]} > ${(q)rcfile}"
    then
        # Without this check a failed osascript would leave us waiting out the
        # whole timeout for a tab that never opened.
        echo "SudoRun: failed to open a terminal tab — command not run" >&2
        return 1
    fi

    # Wait for the marker to be non-empty, not merely present: `>` creates the
    # file before the write lands, so testing -f can race and read back "".
    local timeout=${SUDORUN_TIMEOUT:-300} waited=0
    while [ ! -s "$rcfile" ]; do
        if [ "$waited" -ge "$timeout" ]; then
            echo "SudoRun: timed out after ${timeout}s (password never entered?)" >&2
            [ -f "$log" ] && cat "$log"
            echo "SudoRun: partial log: $log" >&2
            return 124
        fi
        sleep 1
        waited=$((waited + 1))
    done

    [ -f "$log" ] && cat "$log"
    local rc
    rc="$(cat "$rcfile")"
    echo "SudoRun: exit ${rc} (log: $log)" >&2
    # Guard against a non-numeric marker (e.g. tab killed mid-write).
    case "$rc" in
        ''|*[!0-9]*) return 125 ;;
        *) return "$rc" ;;
    esac
}

# Lower-case spelling, since the function reads like a command and zsh is
# case-sensitive.
alias sudorun=SudoRun

# updateprofile: pull latest changes for this scripts repo. Run after pushing
# updates upstream; reload the shell (`exec "$SHELL" -l`) to pick them up.
function updateprofile() {
    ( cd "$SCRIPTDIR" && git pull )
}

# ci: open the claude history picker (-g = global / across projects).
function ci {
    claude-history -g
}

# TabFocus: delegate to the iTerm tab-switcher helper (bound to ^Y).
function TabFocus() {
    $SCRIPTDIR/iterm2-tab-focus.sh
}

# CloseTabsLeft [n]
# Close the n tabs immediately to the LEFT of the current tab in the current
# iTerm2 window (default 1). Never closes more than exist to the left, and never
# touches the current tab or anything to its right.
# Note: iTerm may still pop its "close session with a running job?" confirmation
# if that preference is on.
function CloseTabsLeft() {
    local n="${1:-1}"
    case "$n" in
        ''|*[!0-9]*) echo "usage: CloseTabsLeft [n]" >&2; return 2 ;;
    esac
    osascript - "$n" <<'EOF'
on run argv
    set n to (item 1 of argv) as integer
    tell application "iTerm2"
        tell current window
            -- iTerm2's tab has no usable `index` property, so find the current
            -- tab by matching its current session's id.
            set curId to id of current session of current tab
            set idx to 0
            set i to 0
            repeat with t in tabs
                set i to i + 1
                if (id of current session of t) is curId then set idx to i
            end repeat
            if idx is 0 then return "0"
            set toClose to idx - 1
            if n < toClose then set toClose to n
            -- Closing tab 1 each time shifts the rest left, so repeating it
            -- eats exactly the tabs left of the original current tab.
            repeat toClose times
                close tab 1
            end repeat
            return (toClose as text)
        end tell
    end tell
end run
EOF
}

# alllisten: list every listening TCP socket on the machine (needs sudo).
function alllisten() {
    lsof -nP -iTCP -sTCP:LISTEN
}

# killport <port> [-9|--force]
# Kill every process listening on <port>. Default signal is TERM; pass -9
# (or --force) for SIGKILL. Returns non-zero if nothing was listening.
function killport() {
    local port="$1"
    local sig=TERM
    case "$2" in
        -9|--force|force|kill) sig=KILL ;;
        "") ;;
        *) echo "killport: unknown flag '$2'" >&2; return 2 ;;
    esac
    if [ -z "$port" ]; then
        echo "usage: killport <port> [-9|--force]" >&2
        return 1
    fi
    local pids
    pids=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null)
    if [ -z "$pids" ]; then
        echo "killport: no process listening on port $port" >&2
        return 1
    fi
    echo "killport: SIG$sig -> $(echo $pids | tr '\n' ' ')"
    echo "$pids" | xargs kill -"$sig"
}

# QuickSel: fuzzy-pick a command from ~/temp/quicksel.vim and run it in a new
# iTerm tab. The vim file uses `function NAME` + `write text "CMD"` blocks;
# parse_quicksel.sh extracts them into a name<TAB>cmd table for fzf.
# For a simpler alternative that takes a description<TAB>cmd list directly,
# see quicksel_list.sh.
function QuickSel() {
    sh $SCRIPTDIR/parse_quicksel.sh
}

function QuickSelListExample()
{
echo -e "build\tmake -j8\ntest\tpytest -x\nuse claude in user folder\tcd ~ && claude" | QuickSelList
}

# QuickSelList: fuzzy-pick a command from csv (default: ~/temp/quicksel_list.tsv) that contains description\tcmd.
#
#  The list comes from $QUICKSEL_LIST_FILE(or from stdin if piped). try QuickSelListExample
#
function QuickSelList() {
    if [ -t 0 ]; then
        sh $SCRIPTDIR/quicksel_list.sh
    else
        sh $SCRIPTDIR/quicksel_list.sh -
    fi
}

# ed: open a file in the running nvim-qt instance (via neovim-remote).
# Reads the servername from ~/temp/listen.txt; falls back to launching
# $qtpath directly if nvr can't reach the server.
#   ed path/to/file        # open file
#   ed path/to/file 42     # open at line 42
function ed() {
    local ar="$1"
    local line="$2"
    echo "$ar $line"
    local servername
    servername=$(cat ~/temp/listen.txt)
    if [ -n "$line" ]; then
        local lineArg="+$line"
        echo "nvr --remote $lineArg $ar --servername $servername"
        nvr --remote "$lineArg" "$ar" --servername "$servername"
        if [ $? -eq 1 ]; then
            "$qtpath" "$lineArg" "$ar"
        fi
    else
        echo "nvr --remote $ar --servername $servername"
        nvr --remote "$ar" --servername "$servername"
        if [ $? -eq 1 ]; then
            "$qtpath" "$ar"
        fi
    fi
    osascript -e 'tell application "nvim-qt" to activate' 2>/dev/null
}

findpgid() {
    [ -z "$1" ] && { echo "usage: findpgid <name>" >&2; return 1; }
    # PID, PGID, comm for each match; print where pid == pgid (group leader)
    ps -Ao pid,pgid,comm | awk -v IGNORECASE=1 -v n="$1" \
        '$3 ~ n && $1 == $2 { print $1 }'
}

# mdname [-i DIR] <glob>: Spotlight search by FILE NAME, with real glob
# semantics, case-insensitive. Defaults to the current directory.
#   mdname '*.pdf'
#   mdname -i ~/Documents '*report*.pdf'
# Why not plain mdfind: `mdfind -name X` matches word *prefixes* (so `-name
# port` never finds `xreportx.pdf`), and `kMDItemFSName == "a*b"` honours only
# a leading/trailing '*' — an internal '*' or a '?' silently drops matches.
# So narrow with the pattern's longest literal chunk (index-side, fast), then
# match the basenames here with the glob translated to a regex.
# Only Spotlight-indexed paths are searchable: /private/tmp and other excluded
# volumes always come back empty — use `find` there.
function mdname() {
    local dir="."
    if [ "$1" = "-i" ]; then dir="$2"; shift 2; fi
    local pat="$1"
    if [ -z "$pat" ]; then
        echo "usage: mdname [-i DIR] <glob>   e.g. mdname '*report*.pdf'" >&2
        return 1
    fi

    # longest run of literal (non-wildcard) chars -> the mdfind predicate
    # (empty for a pattern like '*' gives "**", which matches everything —
    # a lone "*" matches nothing, so don't "simplify" that)
    local rest="$pat" seg longest=""
    while [ -n "$rest" ]; do
        seg="${rest%%[*?]*}"
        if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#"$seg"?}"; fi
        [ ${#seg} -gt ${#longest} ] && longest="$seg"
    done

    # glob -> ERE: escape the metachars, then '*' -> [^/]* and '?' -> [^/]
    local rx
    rx=$(printf '%s' "$pat" | sed -e 's/[\\.[()|^$+{}]/\\&/g' \
                                  -e 's/\*/[^\/]*/g' -e 's/?/[^\/]/g')
    mdfind -onlyin "$dir" "kMDItemFSName == \"*$longest*\"c" 2>/dev/null |
        grep -iE "/$rx\$"
}

# stayawake [duration]: keep the Mac awake (prevent display, idle, and system
# sleep) until you press Ctrl-C. Runs in the foreground so there's no leftover
# process to clean up. Pass a duration to auto-release after it elapses —
# accepts bare seconds or a suffixed value (Ns / Nm / Nh).
#   stayawake          # awake until Ctrl-C
#   stayawake 2h       # awake for 2 hours, then release
# extmaindisplay: set the external (non-builtin) display as the main display.
# The "main" display in macOS is whichever screen's origin is at (0,0) in the
# global coordinate space — that's where the menu bar lives. This function
# finds the non-builtin display and, if it isn't already main, rearranges the
# layout so it sits at (0,0) and the builtin is offset to its right.
function extmaindisplay() {
    python3 - <<'PYEOF'
import Quartz, sys

err, display_ids, count = Quartz.CGGetActiveDisplayList(32, None, None)
displays = list(display_ids[:count])

external = next((d for d in displays if not Quartz.CGDisplayIsBuiltin(d)), None)
builtin  = next((d for d in displays if     Quartz.CGDisplayIsBuiltin(d)), None)

if external is None:
    print("extmaindisplay: no external display found", file=sys.stderr)
    sys.exit(1)

if Quartz.CGDisplayIsMain(external):
    print("extmaindisplay: external display is already main")
    sys.exit(0)

ext_w = int(Quartz.CGDisplayBounds(external).size.width)
err, cfg = Quartz.CGBeginDisplayConfiguration(None)
Quartz.CGConfigureDisplayOrigin(cfg, external, 0, 0)
if builtin is not None:
    Quartz.CGConfigureDisplayOrigin(cfg, builtin, ext_w, 0)
err = Quartz.CGCompleteDisplayConfiguration(cfg, Quartz.kCGConfigureForSession)
if err:
    print(f"extmaindisplay: configuration failed (err={err})", file=sys.stderr)
    sys.exit(1)
print("extmaindisplay: done")
PYEOF
}

function stayawake() {
    local secs=0
    if [ -n "$1" ]; then
        case "$1" in
            *h) secs=$(( ${1%h} * 3600 )) ;;
            *m) secs=$(( ${1%m} * 60 )) ;;
            *s) secs=${1%s} ;;
            *[!0-9]*) echo "usage: stayawake [Ns|Nm|Nh]" >&2; return 2 ;;
            *) secs=$1 ;;
        esac
    fi
    if [ "$secs" -gt 0 ]; then
        echo "stayawake: keeping Mac awake for $1 (Ctrl-C to stop early)…"
        caffeinate -dimsu -t "$secs"
    else
        echo "stayawake: keeping Mac awake until Ctrl-C…"
        caffeinate -dimsu
    fi
}

function zudo() {
  sudo -E zsh -c "source $HOME/.zshrc ; $*"
}
function zshdo() {
     zsh -c "source $HOME/.zshrc ; $*"
}

# askclaude: ask Claude a one-off question and print the answer (non-interactive).
# Uses Claude Code's print mode (`claude -p`) with Sonnet, MCP servers as
# configured, and --permission-mode auto so it can actually act: the auto-mode
# classifier approves safe edits / MCP calls / bash by itself and blocks the
# dangerous ones (nothing can prompt in print mode). Takes the question as
# arguments, or reads it from stdin if none are given.
#   askclaude "what is the capital of france?"
#   echo "summarize this" | askclaude
#   cat file.py | askclaude "explain this code"
function askclaude() {
    local flags=(--model sonnet --permission-mode auto)
    if [ -t 0 ]; then
        # No piped input: question must be in the arguments.
        if [ -z "$1" ]; then
            echo "usage: askclaude <question>   (or pipe input)" >&2
            return 1
        fi
        claude -p "${flags[@]}" "$*"
    else
        # Piped input: prepend any arguments as instructions, then the stdin.
        { [ -n "$*" ] && printf '%s\n\n' "$*"; cat; } | claude -p "${flags[@]}"
    fi
}

# searchconv: search past Claude Code conversations for some text, then resume
# the best match right here. Wraps the /search-conversations skill via print mode
# (default model, MCPs as configured). Claude prints the matches plus two marker
# lines (RESUME_DIR / RESUME_UUID) for the top hit, which we parse and resume
# with `claude --resume` in the current shell.
#   searchconv vimspector setup
#   searchconv "that bug with the sandbox"
function searchconv() {
    if [ -z "$1" ]; then
        echo "usage: searchconv <text>" >&2
        return 1
    fi

    local out
    out=$(claude --model opus --effort low -p "/search-conversations $* — show the matches. Then for the single most relevant match, print these two lines last, each alone and exactly in this form (the working directory and session UUID):
RESUME_DIR: <absolute working dir>
RESUME_UUID: <session uuid>
If there is no good match, print 'RESUME_UUID: NONE' instead.")
    printf '%s\n' "$out"

    local dir uuid
    dir=$(printf '%s\n' "$out"  | sed -n 's/^RESUME_DIR: *//p'  | tail -1)
    uuid=$(printf '%s\n' "$out" | sed -n 's/^RESUME_UUID: *//p' | tail -1)
    if [ -z "$uuid" ] || [ "$uuid" = "NONE" ]; then
        echo "searchconv: no conversation to open" >&2
        return 1
    fi

    echo "searchconv: resuming $uuid in ${dir:-$PWD}"
    ( cd "${dir:-$PWD}" && claude --resume "$uuid" )
}

# claude-resume: resume a Claude Code conversation by session id, from any dir.
# Claude scopes `claude --resume` to the current project directory, so we locate
# the transcript for <id> under ~/.claude/projects, read its recorded working
# directory, and resume from there. Accepts a full session id or a unique prefix.
# Extra args pass through to claude, e.g. `claude-resume <id> --model opus`.
#   claude-resume 6c072c4c-2a4b-4c43-a2b9-12389f66df5f
function claude-resume() {
    local id="$1"
    local projects="$HOME/.claude/projects"
    if [ -z "$id" ]; then
        echo "usage: claude-resume <session-id>" >&2
        return 1
    fi

    # Find the transcript: exact <id>.jsonl first, else fall back to a prefix.
    local matches count
    matches=$(find "$projects" -type f -name "$id.jsonl" 2>/dev/null)
    [ -z "$matches" ] && matches=$(find "$projects" -type f -name "$id*.jsonl" 2>/dev/null)
    count=$(printf '%s' "$matches" | grep -c .)

    if [ "$count" -eq 0 ]; then
        echo "claude-resume: no session found for id: $id" >&2
        return 1
    elif [ "$count" -gt 1 ]; then
        echo "claude-resume: ambiguous id '$id' matches $count sessions:" >&2
        printf '%s\n' "$matches" | while read -r m; do
            echo "  $(basename "$m" .jsonl)" >&2
        done
        return 1
    fi

    local file sid dir
    file="$matches"
    sid=$(basename "$file" .jsonl)

    # Recorded working directory (more reliable than decoding the slug, which is
    # lossy when a real path contains '-').
    if command -v jq >/dev/null 2>&1; then
        dir=$(jq -r 'select(.cwd) | .cwd' "$file" 2>/dev/null | head -n1)
    else
        dir=$(grep -o '"cwd":"[^"]*"' "$file" | head -n1 | sed 's/^"cwd":"//; s/"$//')
    fi

    if [ -z "$dir" ]; then
        echo "claude-resume: could not read cwd from $file" >&2
        return 1
    fi
    if [ ! -d "$dir" ]; then
        echo "claude-resume: recorded directory no longer exists: $dir" >&2
        return 1
    fi

    echo "claude-resume: resuming $sid in $dir"
    shift
    ( cd "$dir" && claude --resume "$sid" "$@" )
}

function sclaude-resume() {
    local id="$1"
    local projects="$HOME/.claude/projects"
    if [ -z "$id" ]; then
        echo "usage: sclaude-resume <session-id>" >&2
        return 1
    fi

    local matches count
    matches=$(find "$projects" -type f -name "$id.jsonl" 2>/dev/null)
    [ -z "$matches" ] && matches=$(find "$projects" -type f -name "$id*.jsonl" 2>/dev/null)
    count=$(printf '%s' "$matches" | grep -c .)

    if [ "$count" -eq 0 ]; then
        echo "sclaude-resume: no session found for id: $id" >&2
        return 1
    elif [ "$count" -gt 1 ]; then
        echo "sclaude-resume: ambiguous id '$id' matches $count sessions:" >&2
        printf '%s\n' "$matches" | while read -r m; do
            echo "  $(basename "$m" .jsonl)" >&2
        done
        return 1
    fi

    local file sid dir
    file="$matches"
    sid=$(basename "$file" .jsonl)

    if command -v jq >/dev/null 2>&1; then
        dir=$(jq -r 'select(.cwd) | .cwd' "$file" 2>/dev/null | head -n1)
    else
        dir=$(grep -o '"cwd":"[^"]*"' "$file" | head -n1 | sed 's/^"cwd":"//; s/"$//')
    fi

    if [ -z "$dir" ]; then
        echo "sclaude-resume: could not read cwd from $file" >&2
        return 1
    fi
    if [ ! -d "$dir" ]; then
        echo "sclaude-resume: recorded directory no longer exists: $dir" >&2
        return 1
    fi

    echo "sclaude-resume: resuming $sid in $dir"
    shift
    ( cd "$dir" && scl --resume "$sid" "$@" )
}

# reload: reset the current shell by replacing it with a fresh login shell.
# Clears all in-memory state (functions, aliases, exported vars) and re-sources
# config, while keeping the current working directory (exec preserves cwd).
function reload() {
    exec "${SHELL:-/bin/zsh}" -l
}

# introducegittreealias: install the `git tree` alias in ~/.gitconfig — a
# one-line graph log of all refs. Run once on a new machine.
function introducegittreealias() {
    git config --global alias.tree "log --oneline --decorate --all --graph"
    echo "git tree -> $(git config --global --get alias.tree)"
}

# tmuxaws: ssh into $REMOTEAWS, fuzzy-pick one of its tmux sessions, and attach.
# Cancel the picker (Esc/^C) to back out without connecting.
function tmuxaws() {
    local session
    # The remote shell re-parses the command, so '#S' must stay quoted on the
    # far side too — otherwise '#' starts a comment and -F loses its argument.
    session=$(ssh "$REMOTEAWS" 'tmux list-sessions -F "#S"' 2>/dev/null | fzf --prompt='tmux session> ') || return 0
    ssh -t "$REMOTEAWS" tmux attach -t "$session"
}

# tmuxatt: fuzzy-pick one of the *local* tmux sessions and attach to it.
# Cancel the picker (Esc/^C) to back out. Inside tmux, switches the current
# client instead of attaching (nested attach is refused by tmux).
function tmuxatt() {
    local session
    session=$(tmux list-sessions -F '#S' 2>/dev/null) || { echo "no local tmux sessions" >&2; return 1; }
    session=$(printf '%s\n' "$session" | fzf --prompt='tmux session> ') || return 0
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$session"
    else
        tmux attach -t "$session"
    fi
}
# add-to-path <dir> — prepend a dir to PATH now and persist it by appending an
# export line to this file. Skips if the dir is already on PATH.
add-to-path() {
    local dir="$1"
    [[ -n "$dir" ]] || { echo "usage: add-to-path <dir>" >&2; return 1; }
    dir="${dir:A}"
    [[ -d "$dir" ]] || { echo "add-to-path: not a directory: $dir" >&2; return 1; }
    if [[ ":$PATH:" == *":$dir:"* ]]; then
        echo "add-to-path: already on PATH: $dir"
        return 0
    fi
    export PATH="$dir:$PATH"
    printf 'export PATH="%s:$PATH"\n' "$dir" >> ~/.zshrc
    echo "add-to-path: added $dir (persisted to ~/.zshrc)"
}
