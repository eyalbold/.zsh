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
alias cl=claude-sandboxed
alias cc=claude-sandboxed --continue

# -- Keybindings (emacs-mode in zsh) -----------------------------------------
# Disabled by default. To enable, set SCRIPTS_KEYBINDINGS=1 in config.sh.
if [ "${SCRIPTS_KEYBINDINGS:-0}" = "1" ]; then
    bindkey -e
    bindkey '\e\e[C' forward-word
    bindkey '\e\e[D' backward-word
    bindkey -s '^X' 'QuickSelList\n'    # fuzzy-pick a command from quicksel.vim
    bindkey -s '^E' 'ClaudeZi\n'    # fuzzy search recent folders (using zoxide), open claude there
    bindkey -s '^Y' 'TabFocus\n'    # focus a specific iTerm tab
    bindkey -s '^Q' 'zi\n'          # interactive zoxide
fi


# ClaudeZiStrong: fuzzy search recent folders (using zoxide), then open a new
# terminal tab running `claude` (the unsandboxed CLI) in that directory.
function ClaudeZiStrong() {
    local dir
    dir=$(zoxide query -l | fzf --preview 'ls -la {}' --preview-window=right:50%:wrap) || return 0
    "$SCRIPTDIR/open_in_new_tab.sh" "cd ${(q)dir} && claude"
}

# ClaudeZi: fuzzy search recent folders (using zoxide), then open a new
# terminal tab running the sandboxed `claude-sandboxed` wrapper in that dir.
# This is the default Claude launcher and is bound to ^B.
function ClaudeZi() {
    local dir
    dir=$(zoxide query -l | fzf --preview 'ls -la {}' --preview-window=right:50%:wrap) || return 0
    "$SCRIPTDIR/open_in_new_tab.sh" "cd ${(q)dir} && claude-sandboxed"
}

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
  sudo -E zsh -c "source $HOME/.zshrc && $*"
}

# askclaude: ask Claude a one-off question and print the answer (non-interactive).
# Uses Claude Code's print mode (`claude -p`) with Sonnet and no MCP servers
# loaded (--strict-mcp-config with no --mcp-config = zero MCP servers). Takes the
# question as arguments, or reads it from stdin if none are given.
#   askclaude "what is the capital of france?"
#   echo "summarize this" | askclaude
#   cat file.py | askclaude "explain this code"
function askclaude() {
    local flags=(--model sonnet --strict-mcp-config)
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
    out=$(claude --model opus -p "/search-conversations $* — show the matches. Then for the single most relevant match, print these two lines last, each alone and exactly in this form (the working directory and session UUID):
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
