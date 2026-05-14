# common.sh — shared shell setup sourced by ~/.bashrc and ~/.zshrc.
# Provides aliases, keybindings, and helper functions for the interactive shell.

# -- Aliases ------------------------------------------------------------------
# cl: shortcut for the sandboxed Claude Code wrapper.
# cc: same wrapper but resumes the most recent session.
alias cl=claude-sandboxed
alias cc=claude-sandboxed --continue

# -- Keybindings (emacs-mode in zsh) -----------------------------------------
# Alt+Right / Alt+Left jump by word; the ^X/^B/^Y/^Q chords run named widgets
# that invoke the functions defined below (or zoxide's interactive picker).
bindkey -e
bindkey '\e\e[C' forward-word
bindkey '\e\e[D' backward-word
bindkey -s '^X' 'QuickSelList\n'    # fuzzy-pick a command from quicksel.vim
bindkey -s '^B' 'ClaudeZi\n'    # zoxide-pick a dir, open claude there
bindkey -s '^Y' 'TabFocus\n'    # focus a specific iTerm tab
bindkey -s '^Q' 'zi\n'          # interactive zoxide

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
CUR="$( dirname -- "$SCRIPT_PATH" )"


# ClaudeZiStrong: pick a directory with zoxide+fzf, then open a new iTerm tab
# running `claude` (the unsandboxed CLI) in that directory.
function ClaudeZiStrong() {
    local dir esc cmd
    dir=$(zoxide query -l | fzf --preview 'ls -la {}' --preview-window=right:50%:wrap) || return 0
    cmd="cd ${(q)dir} && claude"
    esc=${cmd//\"/\\\"}
    osascript \
        -e 'tell application "iTerm" to activate' \
        -e 'tell application "iTerm" to if (count of windows) = 0 then create window with default profile' \
        -e 'tell application "iTerm" to tell current window to create tab with default profile' \
        -e "tell application \"iTerm\" to tell current session of current window to write text \"$esc\""
}

# ClaudeZi: same as ClaudeZiStrong but launches the sandboxed wrapper.
# This is the default Claude launcher and is bound to ^B.
function ClaudeZi() {
    local dir esc cmd
    dir=$(zoxide query -l | fzf --preview 'ls -la {}' --preview-window=right:50%:wrap) || return 0
    cmd="cd ${(q)dir} && claude-sandboxed"
    esc=${cmd//\"/\\\"}
    osascript \
        -e 'tell application "iTerm" to activate' \
        -e 'tell application "iTerm" to if (count of windows) = 0 then create window with default profile' \
        -e 'tell application "iTerm" to tell current window to create tab with default profile' \
        -e "tell application \"iTerm\" to tell current session of current window to write text \"$esc\""
}

# ci: open the claude history picker (-g = global / across projects).
function ci {
    claude-history -g
}

# TabFocus: delegate to the iTerm tab-switcher helper (bound to ^Y).
function TabFocus() {
    $CUR/iterm2-tab-focus.sh
}

# alllisten: list every listening TCP socket on the machine (needs sudo).
function alllisten() {
    sudo lsof -nP -iTCP -sTCP:LISTEN
}

# QuickSel: fuzzy-pick a command from ~/temp/quicksel.vim and run it in a new
# iTerm tab. The vim file uses `function NAME` + `write text "CMD"` blocks;
# parse_quicksel.sh extracts them into a name<TAB>cmd table for fzf.
# For a simpler alternative that takes a description<TAB>cmd list directly,
# see quicksel_list.sh.
function QuickSel() {
    sh $CUR/parse_quicksel.sh
}

function QuickSelListExample()
{
echo -e "build\tmake -j8\ntest\tpytest -x" | QuickSelList
}

# QuickSelList: fuzzy-pick a command from csv (default: ~/temp/quicksel_list.tsv) that contains description\tcmd.
#
#  The list comes from $QUICKSEL_LIST_FILE(or from stdin if piped). try QuickSelListExample
#
function QuickSelList() {
    if [ -t 0 ]; then
        sh $CUR/quicksel_list.sh
    else
        sh $CUR/quicksel_list.sh -
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
