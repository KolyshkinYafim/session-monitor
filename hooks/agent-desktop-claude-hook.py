#!/usr/bin/env python3
"""
Agent Desktop — hook for Claude Code and Codex CLI.

Both CLIs speak the same hook protocol (same event names, same stdin payload, same
`hookSpecificOutput.decision`), so one script serves both. `--source <name>` only
decides which agent the island shows on the card.

Two channels:
  1) Append-only JSONL events → Session Monitor island (status / list).
  2) Unix socket monitor.sock → blocking PermissionRequest (Allow/Deny in island).

Contract, non-negotiable:
  * NEVER write to stdout except for PermissionRequest decisions
    (hookSpecificOutput). For other events, stdout pollutes Claude context.
  * NEVER fail the session — swallow every error and exit 0
    (wrapper also forces exit 0). Missing Monitor → silent no-op / Claude UI.
  * Be fast for non-blocking events. PermissionRequest may block for hours.

Input: hook JSON on stdin.
"""

from __future__ import annotations

import fcntl
import json
import os
import socket
import sys
import time


def source_name() -> str:
    """`--source codex` (default claude). Unknown values pass through as-is."""
    argv = sys.argv[1:]
    for i, arg in enumerate(argv):
        if arg == "--source" and i + 1 < len(argv):
            return argv[i + 1].strip().lower() or "claude"
        if arg.startswith("--source="):
            return arg.split("=", 1)[1].strip().lower() or "claude"
    return "claude"


SOURCE = source_name()


def events_path() -> str:
    override = os.environ.get("AGENT_DESKTOP_EVENTS")
    if override:
        return override
    base = os.path.expanduser("~/Library/Application Support/agent-desktop")
    return os.path.join(base, "events.jsonl")


def socket_path() -> str:
    override = os.environ.get("AGENT_DESKTOP_SOCKET")
    if override:
        return override
    base = os.path.expanduser("~/Library/Application Support/agent-desktop")
    return os.path.join(base, "monitor.sock")


TERM_BUNDLES = {
    "iTerm.app": "com.googlecode.iterm2",
    "Apple_Terminal": "com.apple.Terminal",
    "vscode": "com.microsoft.VSCode",
    "Warp": "dev.warp.Warp-Stable",
    "WarpTerminal": "dev.warp.Warp-Stable",
    "ghostty": "com.mitchellh.ghostty",
    "Ghostty": "com.mitchellh.ghostty",
    "Hyper": "co.zeit.hyper",
    "kitty": "net.kovidgoyal.kitty",
    "Alacritty": "org.alacritty",
    "alacritty": "org.alacritty",
    "WezTerm": "com.github.wez.wezterm",
    "Tabby": "org.tabby",
    "zed": "dev.zed.Zed",
}


def terminal_ids():
    tty = None
    try:
        fd = os.open("/dev/tty", os.O_RDONLY)
        try:
            tty = os.ttyname(fd)
        finally:
            os.close(fd)
    except Exception:
        pass
    iterm = os.environ.get("ITERM_SESSION_ID", "")
    iterm_uuid = iterm.split(":", 1)[1] if ":" in iterm else (iterm or None)
    return tty, iterm_uuid


def term_targets() -> dict:
    """Per-terminal handles the island uses to focus the *exact* tab/pane.

    Each terminal exposes its own: kitty needs a window id plus its control socket,
    WezTerm a pane id, tmux a pane inside a socket, VS Code only the workspace path.
    """
    env = os.environ
    ids = {}

    def put(key, value):
        if value:
            ids[key] = str(value)

    put("kittyWindow", env.get("KITTY_WINDOW_ID"))
    put("kittySocket", env.get("KITTY_LISTEN_ON"))
    put("weztermPane", env.get("WEZTERM_PANE"))
    put("weztermSocket", env.get("WEZTERM_UNIX_SOCKET"))
    put("tmuxPane", env.get("TMUX_PANE"))
    # $TMUX = /private/tmp/tmux-501/default,12345,0 → socket path + session index
    tmux = env.get("TMUX")
    if tmux:
        parts = tmux.split(",")
        put("tmuxSocket", parts[0])
        if len(parts) > 2:
            put("tmuxSession", parts[2])
    # Terminal.app hands out a stable per-tab id, nicer than matching on tty.
    put("appleTermSession", env.get("TERM_SESSION_ID"))
    put("windowId", env.get("WINDOWID"))
    return ids


def focus_app():
    term = (os.environ.get("TERM_PROGRAM") or "").strip()
    if term == "vscode":
        # Cursor and the other VS Code forks export TERM_PROGRAM=vscode too, so the host
        # bundle id is the only thing that keeps the island from opening the project in
        # Microsoft's build instead of the editor the session actually runs in.
        if os.environ.get("CURSOR_TRACE_ID"):
            return "com.todesktop.230313mzl4w4u92"
        host = (os.environ.get("__CFBundleIdentifier") or "").strip()
        return host or TERM_BUNDLES["vscode"]
    if term in TERM_BUNDLES:
        return TERM_BUNDLES[term]
    # Ghostty/kitty/wezterm set their own markers even when TERM_PROGRAM is missing.
    if os.environ.get("GHOSTTY_RESOURCES_DIR"):
        return "com.mitchellh.ghostty"
    if os.environ.get("KITTY_WINDOW_ID"):
        return "net.kovidgoyal.kitty"
    if os.environ.get("WEZTERM_PANE"):
        return "com.github.wez.wezterm"
    return term or "com.apple.Terminal"


def waiting_prompt(ntype: str) -> str:
    return {
        "permission_prompt": "Needs permission",
        "idle_prompt": "Waiting — your turn",
        "agent_needs_input": "Needs your input",
        "elicitation_dialog": "Needs your input",
    }.get(ntype, "Waiting for your input")


def _short(value, limit: int) -> str:
    text = str(value).replace("\n", " ").strip()
    return text[: limit - 1] + "…" if len(text) > limit else text


def _basename(path) -> str:
    name = os.path.basename(str(path).rstrip("/"))
    return name or str(path)


def tool_activity(tool: str, tool_input, tool_output=None) -> str:
    """`Read(schema.prisma)` / `Bash(npm test)` — the card line users actually read."""
    args = tool_input if isinstance(tool_input, dict) else {}
    detail = ""
    if tool in ("Read", "Write", "Edit", "MultiEdit", "NotebookEdit"):
        detail = _basename(args.get("file_path") or args.get("notebook_path") or "")
    elif tool == "Bash":
        # `cd /very/long/path && npm test` — the command is the interesting half.
        command = str(args.get("command") or "")
        if command.startswith("cd ") and "&&" in command:
            command = command.split("&&", 1)[1]
        detail = _short(command, 60)
    elif tool in ("Grep", "Glob"):
        detail = _short(args.get("pattern") or args.get("path") or "", 40)
    elif tool == "Task":
        detail = _short(args.get("subagent_type") or args.get("description") or "", 40)
    elif tool in ("WebFetch", "WebSearch"):
        detail = _short(args.get("url") or args.get("query") or "", 50)
    elif tool == "TodoWrite":
        todos = args.get("todos")
        detail = f"{len(todos)} items" if isinstance(todos, list) else ""
    elif tool == "AskUserQuestion":
        # The question lives one level down, so the generic key sweep finds nothing and the
        # permission card degrades to a bare "Allow AskUserQuestion?" — the most common one.
        questions = args.get("questions")
        first = questions[0] if isinstance(questions, list) and questions else None
        if isinstance(first, dict):
            detail = _short(first.get("question") or first.get("header") or "", 60)
    elif tool == "ExitPlanMode":
        detail = _short(args.get("plan") or "", 45)
    else:
        for key in ("file_path", "path", "command", "query", "prompt"):
            if args.get(key):
                detail = _short(args[key], 45)
                break

    line = f"{tool}({detail})" if detail else tool

    # Edits are the one place a size delta is worth the extra glance.
    if tool in ("Edit", "MultiEdit") and isinstance(args.get("new_string"), str):
        old_lines = str(args.get("old_string") or "").count("\n") + 1
        new_lines = args["new_string"].count("\n") + 1
        line += f" +{max(new_lines - old_lines, 0)} −{max(old_lines - new_lines, 0)}"
    return line[:180]


def build_events(data: dict) -> list:
    raw_sid = data.get("session_id")
    if not raw_sid:
        return []
    # Namespaced: Claude and Codex both hand out bare UUIDs, and two agents in the same
    # repo would otherwise share one card.
    # Chat Hub spawns `claude` too, and this hook is installed globally, so the
    # same turn is seen twice. When the Hub tells us which card it already owns,
    # write to that one instead of minting a second — the hook's tool activity
    # and permission prompts then land on the Hub's card rather than a ghost.
    hub_sid = os.environ.get("AGENT_DESKTOP_HUB_SESSION") or ""
    if hub_sid:
        sid = hub_sid
    else:
        sid = raw_sid if raw_sid.startswith(SOURCE + "-") else f"{SOURCE}-{raw_sid}"
    cwd = data.get("cwd") or os.getcwd()
    event = data.get("hook_event_name", "")
    now = int(time.time() * 1000)
    project = os.path.basename(cwd.rstrip("/")) or cwd
    app = os.environ.get("AGENT_DESKTOP_HUB_BUNDLE") or focus_app()
    tty, term_session = terminal_ids()
    targets = term_targets()

    def upsert(title, status, activity=None, model=None):
        session = {
            "id": sid,
            "title": title,
            "project": project,
            "provider": SOURCE,
            "cwd": cwd,
            "status": status,
            "source": "hub" if hub_sid else "terminal",
            "focusApp": app,
            "createdAt": now,
            "updatedAt": now,
        }
        if model:
            session["model"] = model
        if activity:
            session["lastActivity"] = activity
        if tty:
            session["tty"] = tty
        if term_session:
            session["termSession"] = term_session
        if targets:
            session["termIds"] = targets
        return {"type": "session.upsert", "session": session, "ts": now}

    model = data.get("model") or data.get("model_id")

    if event == "SessionStart":
        return [upsert(project, "idle", activity="Session started", model=model)]

    if event == "UserPromptSubmit":
        prompt = (data.get("prompt") or "").strip().replace("\n", " ")
        title = (prompt[:60] + "…") if len(prompt) > 60 else (prompt or project)
        return [upsert(title, "running", activity="You: " + (prompt[:80] if prompt else "…"), model=model)]

    if event == "Notification":
        ntype = data.get("notification_type", "")
        if any(k in ntype for k in ("permission", "input", "idle", "elicitation_dialog")):
            return [{
                "type": "session.question",
                "id": sid,
                "requestId": sid + "-" + str(now),
                "prompt": data.get("message") or waiting_prompt(ntype),
                "ts": now,
            }]
        return []

    if event == "PermissionRequest":
        tool = data.get("tool_name") or data.get("toolName") or "tool"
        summary = tool_activity(tool, data.get("tool_input"))
        if data.get("message"):
            summary = _short(data["message"], 120)
        elif summary == tool:
            summary = f"Allow {tool}?"
        # tool_use_id is stable for this exact call — better than a timestamp when the same
        # tool is requested twice in a row. Claude Code's payload has no such field today,
        # so in practice this is the Codex/future path and ids are not stable for Claude.
        request_id = f"{SOURCE}-{data['tool_use_id']}" if data.get("tool_use_id") else (sid + "-perm-" + str(now))
        return [{
            "type": "session.permission",
            "id": sid,
            "requestId": request_id,
            "summary": summary,
            "ts": now,
        }]

    if event == "PostToolUse":
        tool = data.get("tool_name") or data.get("toolName") or "tool"
        return [{
            "type": "session.message",
            "id": sid,
            "role": "tool",
            "preview": tool_activity(tool, data.get("tool_input"), data.get("tool_output")),
            "ts": now,
        }]

    if event == "Stop":
        # Claude finished its turn. That is "done, your move" — not a permission the
        # user must clear, so it must not inflate the waiting badge.
        # The banner goes FIRST: any incoming message counts as fresh activity and pulls an
        # idle card back to running, so the status has to be the last word of the turn.
        return [
            {
                "type": "session.message",
                "id": sid,
                "role": "assistant",
                "preview": _short(data.get("last_assistant_message") or "Done — your turn", 120),
                "ts": now,
            },
            {"type": "session.status", "id": sid, "status": "idle", "ts": now},
        ]

    if event in ("StopFailure",):
        return [{"type": "session.status", "id": sid, "status": "error", "ts": now}]

    if event == "SessionEnd":
        return [{"type": "session.ended", "id": sid, "reason": "done", "ts": now}]

    return []


def append_events(events: list) -> None:
    if not events:
        return
    path = events_path()
    # Best-effort by contract: an unwritable events file (disk full, root-owned after a sudo
    # run) must not also cost PermissionRequest its socket round-trip, which is appended
    # before it asks the island.
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        # Hooks only append. Rotation/trim is owned by Session Monitor (avoids inode races);
        # the shared lock is what keeps our append out of the bytes it is trimming.
        with open(path, "a", encoding="utf-8") as f:
            try:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            except Exception:
                pass
            for obj in events:
                f.write(json.dumps(obj, ensure_ascii=False) + "\n")
            f.flush()
            try:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            except Exception:
                pass
    except Exception:
        pass


def request_session_id(data: dict) -> str:
    # Same rule as the upsert path: under Chat Hub the permission belongs to the
    # Hub's card, or the island would show it against a session nobody sees.
    hub_sid = os.environ.get("AGENT_DESKTOP_HUB_SESSION")
    if hub_sid:
        return hub_sid
    raw = data.get("session_id") or "unknown"
    return raw if raw.startswith(SOURCE + "-") else f"{SOURCE}-{raw}"


def ask_permission_socket(data: dict, request_id: str, summary: str) -> str | None:
    """Block on monitor.sock for allow/deny. Returns 'allow'|'deny'|None (fail-open)."""
    path = socket_path()
    if not os.path.exists(path):
        return None
    sid = request_session_id(data)
    req = {
        "v": 1,
        "source": SOURCE,
        "event": "PermissionRequest",
        "sessionId": sid,
        "requestId": request_id,
        "summary": summary,
        "payload": data,
    }
    sock = None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        # Connect must be quick — a hung connect would stall the tool call.
        sock.settimeout(2)
        sock.connect(path)
        sock.sendall((json.dumps(req, ensure_ascii=False) + "\n").encode("utf-8"))
        # Hours, not forever — if the app dies mid-wait, eventually fall open.
        sock.settimeout(12 * 3600)
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
        line = buf.split(b"\n", 1)[0].decode("utf-8", errors="replace").strip()
        if not line:
            return None
        obj = json.loads(line)
        decision = (obj.get("decision") or {})
        behavior = (decision.get("behavior") or "").lower()
        if behavior in ("allow", "deny"):
            return behavior
    except Exception:
        return None
    finally:
        if sock is not None:
            try:
                sock.close()
            except Exception:
                pass
    return None


def emit_permission_decision(behavior: str) -> None:
    """Only stdout path — Claude Code reads hookSpecificOutput.

    We never send `updatedInput`: the user approved the call Claude proposed, and
    echoing the arguments back would silently re-assert them.
    """
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {"behavior": behavior},
        }
    }
    sys.stdout.write(json.dumps(out, ensure_ascii=False))
    sys.stdout.flush()


def main() -> None:
    raw = sys.stdin.read()
    data = json.loads(raw) if raw.strip() else {}
    event = data.get("hook_event_name", "")

    if event == "PermissionRequest":
        events = build_events(data)
        append_events(events)
        request_id = "unknown"
        summary = "Needs permission"
        if events:
            request_id = events[0].get("requestId", request_id)
            summary = events[0].get("summary", summary)
        decision = ask_permission_socket(data, request_id, summary)
        if decision:
            emit_permission_decision(decision)
        # No decision → no stdout → Claude uses its own prompt (fail-open).
        return

    append_events(build_events(data))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
