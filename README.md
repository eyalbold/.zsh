# scripts/

Shell helpers sourced from `~/.bashrc` / `~/.zshrc` via `common.sh`, plus a couple of standalone tools they call out to.

## Files

| File | Kind | Purpose |
| --- | --- | --- |
| `common.sh` | sourced | Aliases, keybindings, and helper functions for the interactive shell. |
| `claude-sandboxed` | executable | Sandboxed wrapper around the Claude Code CLI (aliased to `cl` / `cc`). |
| `install.sh` | executable | One-shot installer — clones the repo to `~/scripts` and wires `common.sh` into the user's shell rc. |

## Installation

Six-liner:

```sh
## Pre-req zoxide
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc

## Pre-req fzf 
brew install fzf

## Actual installer

curl -fsSL https://raw.githubusercontent.com/eyalbold/.zsh/refs/heads/master/install.sh | sh
```

The installer:

1. `cd ~`
2. Clones `eyalbold/.zsh` into `~/scripts` (skips if a checkout is already there).
3. Picks `~/.zshrc` or `~/.bashrc` based on `$SHELL` (falls back to `~/.profile`) and appends `. ~/scripts/common.sh` if it isn't there already.
4. Symlinks `~/.local/bin/claude-sandboxed` → `~/scripts/claude-sandboxed` (creates `~/.local/bin` if needed; warns if that dir isn't on `$PATH`).

Then reload: `exec "$SHELL" -l`.

### Manual install

```sh
git clone https://github.com/eyalbold/.zsh.git ~/scripts
echo '. ~/scripts/common.sh' >> ~/.zshrc   # or ~/.bashrc
```

`common.sh` auto-detects its own directory and exports it as `$CUR`, so sibling scripts (`parse_quicksel.sh`, `quicksel_list.sh`, `open_in_new_tab.sh`, `iterm2-tab-focus.sh`) are found regardless of how the file is sourced.

## Aliases

| Alias | Expands to |
| --- | --- |
| `cl` | `claude-sandboxed` |
| `cc` | `claude-sandboxed --continue` |

## Keybindings (zsh, emacs mode)

| Chord | Widget | Effect |
| --- | --- | --- |
| `Alt+→` / `Alt+←` | `forward-word` / `backward-word` | Word-wise cursor motion. |
| `^X` | `QuickSelList` | Fuzzy-pick from `~/temp/quicksel_list.tsv` and run in a new terminal tab. |
| `^B` | `ClaudeZi` | Fuzzy search recent folders (using zoxide), open `claude-sandboxed` there. |
| `^Y` | `TabFocus` | Invoke the iTerm tab-focus helper. |
| `^Q` | `zi` | Fuzzy search recent folders (using zoxide) and `cd` there. |

## Functions

### Claude launchers
- **`ClaudeZi`** — fuzzy search recent folders (using zoxide) → new terminal tab running `claude-sandboxed`. Default launcher, bound to `^B`.
- **`ClaudeZiStrong`** — fuzzy search recent folders (using zoxide) → new terminal tab running the unsandboxed `claude`.
- **`ci`** — open `claude-history -g` (global history picker).

### Command pickers
- **`QuickSelList`** — fzf over `~/temp/quicksel_list.tsv` (description⇥cmd lines, parsed by `quicksel_list.sh`). Accepts piped stdin too. Bound to `^X`.
- **`QuickSelListExample`** — demo that pipes two entries into `QuickSelList`.

### Misc
- **`updateprofile`** — `git pull` in `~/scripts` to fetch the latest version of this repo. Run `exec "$SHELL" -l` afterwards to pick up changes.
- **`TabFocus`** — runs `iterm2-tab-focus.sh` (iTerm2 only).
- **`alllisten`** — `sudo lsof -nP -iTCP -sTCP:LISTEN` — every listening TCP socket on the machine.
- **`ed <file> [line]`** — open file (optionally at line N) in the running `nvim-qt` instance via `nvr`. Reads servername from `~/temp/listen.txt`; falls back to `$qtpath` if nvr fails.

## QuickSel list format

`quicksel_list.sh` reads one entry per line, **description and command separated by a literal TAB**. Lines starting with `#` and blank lines are ignored.

```tsv
# description<TAB>command
build	make -j8
test	pytest -x
notebook	cd ~/notebooks && jupyter lab
```

Input precedence (first match wins):

1. Arg `-` → read from stdin.
2. First positional arg → path to a tsv file.
3. `$QUICKSEL_LIST_FILE` env var.
4. `~/temp/quicksel_list.tsv` (default).

You can try it by running `QuickSelListExample`. 
Pick an entry in fzf → the command runs in a new tab of the current terminal app (iTerm2 or macOS Terminal.app; dispatched via `$TERM_PROGRAM` by `open_in_new_tab.sh`).

### more files 

| `parse_quicksel.sh` | executable | Parses `~/temp/quicksel.vim` into a name⇥cmd table and runs the picked command in a new terminal tab. |
| `quicksel_list.sh` | executable | Same picker UX as `parse_quicksel.sh`, but reads a plain `description⇥cmd` list instead. |
| `open_in_new_tab.sh` | executable | Helper used by the launchers above — opens a command in a new tab of the current terminal app (iTerm2 or Terminal.app, dispatched via `$TERM_PROGRAM`). |
| `iterm2-tab-focus.sh` | executable | Switch focus to a specific iTerm tab (bound to `^Y`). iTerm2 only. |

