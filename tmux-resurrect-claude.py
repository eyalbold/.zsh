#!/usr/bin/env python3
"""Make tmux-resurrect bring Claude Code *conversations* back, not empty shells.

tmux-resurrect only re-execs programs listed in @resurrect-processes, and even
with `claude` added it would relaunch a fresh conversation: the saved command
line is useless here (panes save as bare `claude`, or as `` when Claude was
exec'd), so the session id has to come from somewhere else.

Claude Code registers every live session at ``~/.claude/sessions/<pid>.json``:

    {"pid": 64908, "sessionId": "82f534c2-…", "cwd": "/Users/eyalkarni",
     "kind": "interactive", "tmux": "6:@10.%11", …}

i.e. pid -> (tmux session name, window id, pane id, claude session id, cwd).
Window/pane ids (@10/%11) are per-tmux-server and do NOT survive a restart, so
`save` resolves them, while the server is still up, to the session name +
window/pane *index* that resurrect actually restores. `restore` then replays
`claude --resume <id>` into each of those panes.

Wire up in ~/.config/tmux/tmux.conf.local:

    set -g @resurrect-hook-post-save-all    '~/scripts/tmux-resurrect-claude.py save'
    set -g @resurrect-hook-post-restore-all '~/scripts/tmux-resurrect-claude.py restore'

Set CLAUDE_TMUX_RESURRECT=0 to disable without unhooking.
"""
from __future__ import annotations

import glob
import json
import os
import shlex
import subprocess
import sys

HOME = os.environ.get("HOME") or os.path.expanduser("~")
REGISTRY = os.path.join(HOME, ".claude", "sessions")
MAP_PATH = os.environ.get("CLAUDE_TMUX_RESURRECT_MAP") or os.path.join(
    HOME, ".local", "share", "tmux", "resurrect", "claude-sessions.txt")

# Panes whose foreground command is one of these are considered free to reuse.
SHELLS = {"zsh", "bash", "sh", "fish", "-zsh", "-bash", "dash", "ksh"}


def tmux(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["tmux", *args], capture_output=True,
                          encoding="utf-8", errors="replace", timeout=5)


def alive(pid: int) -> bool:
    """True if the pid exists. Claude removes its registry file on a clean exit,
    but a SIGKILL / crash / reboot leaves it behind."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except (OverflowError, ValueError):
        return False
    return True


def live_claude_sessions() -> list[dict]:
    """Registry entries for live, interactive, inside-tmux Claude sessions."""
    out = []
    try:
        names = os.listdir(REGISTRY)
    except OSError:
        return out
    for name in names:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(REGISTRY, name)) as f:
                d = json.load(f)
        except (OSError, ValueError):
            continue
        # kind != interactive is a background agent — it has no pane to restore.
        if d.get("kind") != "interactive" or not d.get("tmux"):
            continue
        if not (d.get("sessionId") and d.get("cwd")):
            continue
        try:
            pid = int(d["pid"])
        except (KeyError, TypeError, ValueError):
            continue
        if not alive(pid):
            continue
        out.append(d)
    # Oldest first, so a stale duplicate on the same pane loses to the newer one.
    out.sort(key=lambda d: d.get("updatedAt") or d.get("startedAt") or 0)
    return out


def pane_coords(pane_id: str) -> tuple[str, str, str] | None:
    """%11 -> (session_name, window_index, pane_index), the coordinates that
    tmux-resurrect saves and restores. None if the pane is gone."""
    r = tmux("display-message", "-pt", pane_id,
             "-F", "#{session_name}\t#{window_index}\t#{pane_index}")
    if r.returncode != 0:
        return None
    parts = r.stdout.rstrip("\n").split("\t")
    if len(parts) != 3 or not parts[0]:
        return None
    return parts[0], parts[1], parts[2]


def has_transcript(session_id: str) -> bool:
    """Whether the id is actually resumable yet.

    A pane that was /clear'ed and never prompted again registers a brand-new id
    with no transcript behind it; restoring that dies with "No conversation found
    with session ID". Globbing every project dir (rather than deriving
    ~/.claude/projects/<slug-of-cwd>/) both skips reimplementing Claude's
    cwd->slug rule and matches how `claude --resume` looks ids up.
    """
    return bool(glob.glob(os.path.join(
        HOME, ".claude", "projects", "*", session_id + ".jsonl")))


def save() -> int:
    rows = {}
    unwritten = 0
    for d in live_claude_sessions():
        # "6:@10.%11" — the pane id after the last '.' is all we need; the
        # session name is re-read from tmux so a renamed session stays correct.
        pane_id = d["tmux"].rsplit(".", 1)[-1]
        if not pane_id.startswith("%"):
            continue
        coords = pane_coords(pane_id)
        if coords is None:
            continue
        if not has_transcript(d["sessionId"]):
            unwritten += 1
            continue
        rows[coords] = (d["sessionId"], d["cwd"])

    os.makedirs(os.path.dirname(MAP_PATH), exist_ok=True)
    tmp = MAP_PATH + ".tmp"
    with open(tmp, "w") as f:
        for (sess, win, pane), (sid, cwd) in sorted(rows.items()):
            f.write(f"{sess}\t{win}\t{pane}\t{sid}\t{cwd}\n")
    os.replace(tmp, MAP_PATH)
    extra = f", skipped {unwritten} with no transcript yet" if unwritten else ""
    print(f"saved {len(rows)} claude session(s) -> {MAP_PATH}{extra}")
    return 0


def restore() -> int:
    try:
        lines = open(MAP_PATH).read().splitlines()
    except OSError:
        print(f"no claude session map at {MAP_PATH}")
        return 0

    # One tmux call for every pane's foreground command, so we can tell an
    # idle restored shell from a pane that is already running something.
    r = tmux("list-panes", "-a", "-F",
             "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_current_command}")
    current = {}
    if r.returncode == 0:
        for ln in r.stdout.splitlines():
            p = ln.split("\t")
            if len(p) == 4:
                current[(p[0], p[1], p[2])] = p[3]

    done = skipped = 0
    for ln in lines:
        parts = ln.split("\t")
        if len(parts) != 5:
            continue
        sess, win, pane, sid, cwd = parts
        key = (sess, win, pane)
        cmd = current.get(key)
        if cmd is None:
            skipped += 1
            continue
        # Only type into a pane sitting at a shell prompt. Anything else is
        # either already a Claude session or a program we must not interrupt.
        if cmd not in SHELLS:
            skipped += 1
            continue
        target = f"{sess}:{win}.{pane}"
        # cd first: `/resume`-style id lookup is scoped to the project dir, and
        # a resumed session inherits the cwd it was launched from.
        keys = f"cd {shlex.quote(cwd)} && claude --resume {shlex.quote(sid)}"
        if tmux("send-keys", "-t", target, keys, "Enter").returncode == 0:
            done += 1
        else:
            skipped += 1
    print(f"claude: resumed {done} pane(s), skipped {skipped}")
    return 0


def main() -> int:
    if os.environ.get("CLAUDE_TMUX_RESURRECT") == "0":
        return 0
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "save":
        return save()
    if action == "restore":
        return restore()
    print(f"usage: {os.path.basename(sys.argv[0])} save|restore", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.TimeoutExpired:
        # Never let a hung tmux call block a resurrect save/restore.
        sys.exit(0)
