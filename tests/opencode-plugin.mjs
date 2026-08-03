// Drives the OpenCode plugin with the bus events OpenCode would emit, so we can see the
// island react without launching a real `opencode` session.
//
//   node tests/opencode-plugin.mjs
//
// Session Monitor must be running (its socket is the only thing the plugin talks to).

import { AgentDesktop } from "../hooks/opencode/agent-desktop.js";

const SESSION = "test-" + Date.now();

const plugin = await AgentDesktop({
  directory: "/Users/yafimkolyshkin/Desktop/agent-desktop-suite",
  worktree: "/Users/yafimkolyshkin/Desktop/agent-desktop-suite",
});

const bus = (type, properties) => plugin.event({ event: { type, properties } });

console.log("session.created");
await bus("session.created", { sessionID: SESSION });

console.log("tool.execute.before ×2");
await plugin["tool.execute.before"]({ sessionID: SESSION, tool: "read" }, { args: { filePath: "/tmp/demo/prisma/schema.prisma" } });
await plugin["tool.execute.before"]({ sessionID: SESSION, tool: "bash" }, { args: { command: "npm test -- --watch=false" } });

console.log("permission.asked");
await bus("permission.asked", { sessionID: SESSION, permissionID: "perm-1", title: "Run rm -rf build" });

console.log("permission.replied → session.idle");
await bus("permission.replied", { sessionID: SESSION });
await bus("session.idle", { sessionID: SESSION });

console.log(`done — look for the card "opencode-${SESSION}" in the island`);
