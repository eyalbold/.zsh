#!/usr/bin/env bash
# quicksel_menu.sh — non-interactive back end for GUIs that want to expose the
# QuickSelList entries as a native menu (e.g. the claude-fleet menu-bar icon).
# Same list and same launcher as quicksel_list.sh, minus fzf.
#
#   quicksel_menu.sh list        # print the clean "description<TAB>cmd" rows
#   quicksel_menu.sh run <cmd>   # run <cmd> in a new tab of the current terminal
#
# Input precedence for the list, as in quicksel_list.sh:
#   1. $QUICKSEL_LIST_FILE   2. ~/temp/quicksel_list.tsv

set -euo pipefail

# $SCRIPTDIR is exported by common.sh; fall back to this script's directory when
# quicksel_menu.sh is invoked standalone (which is the GUI case).
: "${SCRIPTDIR:=$( dirname -- "${BASH_SOURCE[0]}" )}"

case "${1:-}" in
    list)
        file="${QUICKSEL_LIST_FILE:-$HOME/temp/quicksel_list.tsv}"
        [[ -f "$file" ]] || { echo "no file: $file" >&2; exit 1; }
        # Strip comments/blank lines, keep only well-formed description<TAB>cmd rows.
        awk -F'\t' '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { next }
            NF >= 2 { print }
        ' "$file"
        ;;
    run)
        [[ $# -ge 2 ]] || { echo "usage: quicksel_menu.sh run <cmd>" >&2; exit 2; }
        "$SCRIPTDIR/open_in_new_tab.sh" "$2"
        ;;
    *)
        echo "usage: quicksel_menu.sh list | run <cmd>" >&2
        exit 2
        ;;
esac
