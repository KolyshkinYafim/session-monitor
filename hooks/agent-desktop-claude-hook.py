#!/usr/bin/env python3
"""
Agent Desktop — Claude Code hook.

Bridges terminal Claude Code sessions into the Session Monitor island by appending
SessionEvent lines to the shared JSONL bridge. Registered globally in
~/.claude/settings.json for SessionStart / UserPromptSubmit / Notification / Stop /
SessionEnd (see install.sh).

Contract, non-negotiable:
  * NEVER write to stdout — for UserPromptSubmit/SessionStart, stdout is injected into
    Claude's context. All diagnostics go nowhere; we only append to the events file.
  * NEVER fail the session — swallow every error and exit 0.
  * Be fast and non-blocking.

Input: hook JSON on stdin (always has session_id, cwd, hook_event_name).
Output: appended lines to $AGENT_DESKTOP_EVENTS or the default bridge path.
"""

import sys
import os
import json
import time


def events_path():
    override = os.environ.get("AGENT_DESKTOP_EVENTS")
    if override:
        return override
    base = os.path.expanduser("~/Library/Application Support/agent-desktop")
    return os.path.join(base, "events.jsonl")


# TERM_PROGRAM value -> macOS bundle identifier, so the island can focus the host terminal.
TERM_BUNDLES = {
    "iTerm.app": "com.googlecode.iterm2",
    "Apple_Terminal": "com.apple.Terminal",
    "vscode": "com.microsoft.VSCode",
    "Warp": "dev.warp.Warp-Stable",
    "WarpTerminal": "dev.warp.Warp-Stable",
    "ghostty": "com.mitchellh.ghostty",
    "Hyper": "co.zeit.hyper",
    "kitty": "net.kovidgoyal.kitty",
    "Alacritty": "org.alacritty",
    "alacritty": "org.alacritty",
    "WezTerm": "com.github.wez.wezterm",
    "Tabby": "org.tabby",
}


def terminal_ids():
    """Best-effort identifiers to focus the *exact* terminal tab later."""
    tty = None
    try:
        fd = os.open("/dev/tty", os.O_RDONLY)
        try:
            tty = os.ttyname(fd)  # e.g. /dev/ttys004
        finally:
            os.close(fd)
    except Exception:
        pass
    # iTerm2 exposes a per-session UUID via $ITERM_SESSION_ID = "w0t0p0:UUID".
    iterm = os.environ.get("ITERM_SESSION_ID", "")
    iterm_uuid = iterm.split(":", 1)[1] if ":" in iterm else (iterm or None)
    return tty, iterm_uuid


def focus_app():
    term = (os.environ.get("TERM_PROGRAM") or "").strip()
    if term in TERM_BUNDLES:
        return TERM_BUNDLES[term]
    # Unknown terminal: pass the raw name (Session Monitor tries bundle id then name),
    # falling back to Terminal.app so a click still lands somewhere sensible.
    return term or "com.apple.Terminal"


def waiting_prompt(ntype):
    return {
        "permission_prompt": "Needs permission",
        "idle_prompt": "Waiting — your turn",
        "agent_needs_input": "Needs your input",
        "elicitation_dialog": "Needs your input",
    }.get(ntype, "Waiting for your input")


def build_events(data):
    sid = data.get("session_id")
    if not sid:
        return []
    cwd = data.get("cwd") or os.getcwd()
    event = data.get("hook_event_name", "")
    now = int(time.time() * 1000)
    project = os.path.basename(cwd.rstrip("/")) or cwd
    app = focus_app()
    tty, term_session = terminal_ids()

    def upsert(title, status):
        session = {
            "id": sid,
            "title": title,
            "project": project,
            "provider": "claude",
            "cwd": cwd,
            "status": status,
            "focusApp": app,
            "createdAt": now,
            "updatedAt": now,
        }
        if tty:
            session["tty"] = tty
        if term_session:
            session["termSession"] = term_session
        return {"type": "session.upsert", "session": session, "ts": now}

    if event == "SessionStart":
        return [upsert("Claude · " + project, "idle")]

    if event == "UserPromptSubmit":
        prompt = (data.get("prompt") or "").strip().replace("\n", " ")
        title = (prompt[:60] + "…") if len(prompt) > 60 else (prompt or ("Claude · " + project))
        return [upsert(title, "running")]

    if event == "Notification":
        ntype = data.get("notification_type", "")
        if any(k in ntype for k in ("permission", "input", "idle", "elicitation_dialog")):
            return [{
                "type": "session.question",
                "id": sid,
                "requestId": sid + "-" + str(now),
                "prompt": waiting_prompt(ntype),
                "ts": now,
            }]
        return []

    if event == "Stop":
        # Claude finished the turn — it is now the user's move.
        return [{"type": "session.status", "id": sid, "status": "waiting_input", "ts": now}]

    if event == "SessionEnd":
        return [{"type": "session.ended", "id": sid, "reason": "done", "ts": now}]

    return []


def main():
    raw = sys.stdin.read()
    data = json.loads(raw) if raw.strip() else {}
    events = build_events(data)
    if not events:
        return
    path = events_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8") as f:
        for obj in events:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
