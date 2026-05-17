#!/usr/bin/env sh
# Installer for eyalbold/.zsh — clones this repo into ~/scripts and wires it
# into the user's shell rc file.
#
# Run with:
#   curl -fsSL https://raw.githubusercontent.com/eyalbold/.zsh/refs/heads/master/install.sh | sh
#
# What it does:
#   1. cd ~
#   2. git clone https://github.com/eyalbold/.zsh.git ~/scripts  (skips if exists)
#   3. appends `. ~/scripts/common.sh` to ~/.zshrc or ~/.bashrc, picked from $SHELL
#   4. symlinks ~/.local/bin/claude-sandboxed -> ~/scripts/claude-sandboxed

set -eu

REPO_URL="https://github.com/eyalbold/.zsh.git"
DEST="$HOME/scripts"
SRC_LINE=". ~/scripts/common.sh"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/claude-sandboxed"
BIN_TARGET="$DEST/claude-sandboxed"

cd "$HOME"

# -- 1. clone (or report that it already exists) -----------------------------
if [ -d "$DEST" ]; then
    if [ -d "$DEST/.git" ]; then
        echo "==> $DEST already exists (git repo). Skipping clone."
    else
        echo "!! $DEST exists but is not a git checkout. Refusing to overwrite." >&2
        echo "   Move or remove it, then re-run the installer." >&2
        exit 1
    fi
else
    echo "==> Cloning $REPO_URL into $DEST"
    git clone "$REPO_URL" "$DEST"
fi

# -- 2. pick rc file based on the user's login shell -------------------------
case "${SHELL:-}" in
    */zsh)  RC="$HOME/.zshrc"  ;;
    */bash) RC="$HOME/.bashrc" ;;
    *)
        # Fallback: prefer an existing rc, else default to .profile.
        if   [ -f "$HOME/.zshrc"   ]; then RC="$HOME/.zshrc"
        elif [ -f "$HOME/.bashrc"  ]; then RC="$HOME/.bashrc"
        else RC="$HOME/.profile"
        fi
        echo "==> \$SHELL not recognized; using $RC"
        ;;
esac

# -- 3. append the source line if it's not there already ---------------------
touch "$RC"
if grep -Fqx "$SRC_LINE" "$RC"; then
    echo "==> $RC already sources common.sh. Nothing to add."
else
    {
        printf '\n# Added by eyalbold/.zsh installer on %s\n' "$(date +%Y-%m-%d)"
        printf '%s\n' "$SRC_LINE"
    } >> "$RC"
    echo "==> Appended source line to $RC"
fi

# -- 4. symlink claude-sandboxed into ~/.local/bin ---------------------------
mkdir -p "$BIN_DIR"
if [ -L "$BIN_LINK" ] && [ "$(readlink "$BIN_LINK")" = "$BIN_TARGET" ]; then
    echo "==> $BIN_LINK already points to $BIN_TARGET. Nothing to do."
elif [ -e "$BIN_LINK" ] || [ -L "$BIN_LINK" ]; then
    echo "!! $BIN_LINK exists and points somewhere else. Leaving it alone." >&2
    echo "   Remove it and re-run if you want the installer to manage it." >&2
else
    ln -s "$BIN_TARGET" "$BIN_LINK"
    echo "==> Linked $BIN_LINK -> $BIN_TARGET"
fi

case ":${PATH:-}:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Note: $BIN_DIR is not on \$PATH. Add it to your rc if you want the symlink to be usable." ;;
esac

echo
echo "Done. Reload your shell:  exec \"\$SHELL\" -l"
