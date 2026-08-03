// Agent Desktop — OpenCode plugin.
//
// OpenCode has no hook protocol like Claude Code or Codex: it loads JS plugins and calls
// them with bus events (https://opencode.ai/docs/plugins/). So instead of a per-event
// process we keep one tiny module that forwards session state into the island's socket.
//
// Contract, same as the CLI hooks:
//   * never throw into the agent — every failure is swallowed;
//   * never block a tool call — the socket write is fire-and-forget with a short timeout;
//   * if the monitor is down, do nothing at all.
//
// Install: hooks/install-opencode-plugin.sh (copies this into ~/.config/opencode/plugins/).

import { Socket } from "net";
import { homedir } from "os";
import { basename, join } from "path";

const SOCKET_PATH =
  process.env.AGENT_DESKTOP_SOCKET ||
  join(homedir(), "Library", "Application Support", "agent-desktop", "monitor.sock");

const PROVIDER = "opencode";
const CONNECT_TIMEOUT_MS = 1500;
const DEBUG = process.env.AGENT_DESKTOP_DEBUG === "1";

/** Diagnostics only — silent unless AGENT_DESKTOP_DEBUG=1, never thrown at the agent. */
function debug(...args) {
  if (DEBUG) console.error("[agent-desktop]", ...args);
}

/** Terminal bundle ids so the island can focus the window this session runs in. */
const TERM_BUNDLES = {
  "iTerm.app": "com.googlecode.iterm2",
  Apple_Terminal: "com.apple.Terminal",
  vscode: "com.microsoft.VSCode",
  Warp: "dev.warp.Warp-Stable",
  WarpTerminal: "dev.warp.Warp-Stable",
  ghostty: "com.mitchellh.ghostty",
  Ghostty: "com.mitchellh.ghostty",
  kitty: "net.kovidgoyal.kitty",
  WezTerm: "com.github.wez.wezterm",
  Alacritty: "org.alacritty",
  Hyper: "co.zeit.hyper",
  zed: "dev.zed.Zed",
};

function focusApp() {
  const term = (process.env.TERM_PROGRAM || "").trim();
  if (term === "vscode") {
    // Cursor and the other VS Code forks export TERM_PROGRAM=vscode too, so the host
    // bundle id is the only thing that keeps the island from opening the project in
    // Microsoft's build instead of the editor the session actually runs in.
    if (process.env.CURSOR_TRACE_ID) return "com.todesktop.230313mzl4w4u92";
    return (process.env.__CFBundleIdentifier || "").trim() || TERM_BUNDLES.vscode;
  }
  if (TERM_BUNDLES[term]) return TERM_BUNDLES[term];
  if (process.env.GHOSTTY_RESOURCES_DIR) return "com.mitchellh.ghostty";
  if (process.env.KITTY_WINDOW_ID) return "net.kovidgoyal.kitty";
  if (process.env.WEZTERM_PANE) return "com.github.wez.wezterm";
  return term || "com.apple.Terminal";
}

function termIds() {
  const env = process.env;
  const ids = {};
  const put = (key, value) => {
    if (value) ids[key] = String(value);
  };
  put("kittyWindow", env.KITTY_WINDOW_ID);
  put("kittySocket", env.KITTY_LISTEN_ON);
  put("weztermPane", env.WEZTERM_PANE);
  put("weztermSocket", env.WEZTERM_UNIX_SOCKET);
  put("tmuxPane", env.TMUX_PANE);
  if (env.TMUX) {
    const parts = env.TMUX.split(",");
    put("tmuxSocket", parts[0]);
    if (parts.length > 2) put("tmuxSession", parts[2]);
  }
  put("appleTermSession", env.TERM_SESSION_ID);
  return ids;
}

function itermSession() {
  const raw = process.env.ITERM_SESSION_ID || "";
  return raw.includes(":") ? raw.split(":").slice(1).join(":") : raw || undefined;
}

/** One line of NDJSON, then done. Never rejects. */
function send(payload) {
  return new Promise((resolve) => {
    let done = false;
    const finish = () => {
      if (!done) {
        done = true;
        resolve();
      }
    };
    try {
      const sock = new Socket();
      sock.setTimeout(CONNECT_TIMEOUT_MS, () => {
        sock.destroy();
        finish();
      });
      sock.on("error", (err) => {
        debug("socket error", err?.code, SOCKET_PATH);
        finish();
      });
      sock.on("close", finish);
      sock.on("connect", () => {
        sock.end(JSON.stringify(payload) + "\n");
      });
      sock.connect({ path: SOCKET_PATH });
    } catch {
      finish();
    }
  });
}

const shorten = (value, limit) => {
  const text = String(value ?? "").replace(/\s+/g, " ").trim();
  return text.length > limit ? text.slice(0, limit - 1) + "…" : text;
};

/** `read(schema.prisma)` / `bash(npm test)` — same card line the CLI hooks produce. */
function toolActivity(tool, args = {}) {
  const name = String(tool || "tool");
  let detail = "";
  const path = args.filePath || args.file_path || args.path;
  if (path) detail = basename(String(path));
  else if (args.command) detail = shorten(args.command, 60);
  else if (args.pattern) detail = shorten(args.pattern, 40);
  else if (args.query) detail = shorten(args.query, 50);
  else if (args.url) detail = shorten(args.url, 50);
  return detail ? `${name}(${detail})` : name;
}

export const AgentDesktop = async ({ directory, worktree }) => {
  const cwd = worktree || directory || process.cwd();
  const project = basename(String(cwd).replace(/\/+$/, "")) || String(cwd);
  const seen = new Set();

  const sessionId = (raw) => `${PROVIDER}-${raw}`;

  async function upsert(rawId, { title, status, activity }) {
    if (!rawId) return;
    const id = sessionId(rawId);
    seen.add(id);
    const session = {
      id,
      title: title || project,
      project,
      provider: PROVIDER,
      cwd,
      status,
      source: "terminal",
      focusApp: focusApp(),
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    if (activity) session.lastActivity = activity;
    const term = itermSession();
    if (term) session.termSession = term;
    const ids = termIds();
    if (Object.keys(ids).length) session.termIds = ids;
    await send({ type: "session.upsert", session, ts: Date.now() });
  }

  async function status(rawId, value) {
    if (!rawId) return;
    await send({ type: "session.status", id: sessionId(rawId), status: value, ts: Date.now() });
  }

  async function activity(rawId, preview, role = "tool") {
    if (!rawId || !preview) return;
    await send({
      type: "session.message",
      id: sessionId(rawId),
      role,
      preview: preview.slice(0, 180),
      ts: Date.now(),
    });
  }

  /** Bus payloads keep the session id under different names depending on the event. */
  const idOf = (props = {}) =>
    props.sessionID || props.sessionId || props.session?.id || props.info?.sessionID;

  return {
    event: async ({ event }) => {
      try {
        const type = event?.type;
        const props = event?.properties ?? {};
        const id = idOf(props);

        switch (type) {
          case "session.created":
            await upsert(id, { status: "idle", activity: "Session started" });
            break;
          case "session.updated":
          case "session.status":
            if (!seen.has(sessionId(id))) {
              await upsert(id, { status: "running" });
            } else {
              await status(id, "running");
            }
            break;
          case "session.idle":
            // OpenCode finished its turn — your move, not a permission to clear.
            // The banner goes first: any incoming message counts as fresh activity and
            // pulls an idle card back to running, so the status has to land last.
            await activity(id, "Done — your turn", "assistant");
            await status(id, "idle");
            break;
          case "session.error":
            await status(id, "error");
            break;
          case "session.deleted":
            if (id) await send({ type: "session.ended", id: sessionId(id), reason: "done", ts: Date.now() });
            break;
          case "permission.asked":
            if (id) {
              await send({
                type: "session.question",
                id: sessionId(id),
                requestId: `${PROVIDER}-${props.permissionID || props.id || Date.now()}`,
                prompt: shorten(props.title || props.description || "Needs permission", 120),
                ts: Date.now(),
              });
            }
            break;
          case "permission.replied":
            await status(id, "running");
            break;
          default:
            break;
        }
      } catch (err) {
        // A monitor problem must never surface inside the agent.
        debug("event handler failed", err);
      }
    },

    "tool.execute.before": async (input, output) => {
      try {
        const id = input?.sessionID || input?.sessionId;
        if (!seen.has(sessionId(id))) {
          await upsert(id, { status: "running" });
        }
        await activity(id, toolActivity(input?.tool, output?.args));
      } catch (err) {
        debug("tool.execute.before failed", err);
      }
    },
  };
};

export default AgentDesktop;
