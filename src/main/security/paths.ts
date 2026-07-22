import { homedir, tmpdir } from 'node:os'
import { resolve, sep } from 'node:path'
import { agentDesktopEventsPath } from '@shared/bridge-path'

function underRoot(filePath: string, root: string): boolean {
  const resolved = resolve(filePath)
  const base = resolve(root)
  return resolved === base || resolved.startsWith(base + sep)
}

/** Roots adapters may watch/read for SessionEvent discovery. */
export function allowedWatchRoots(): string[] {
  const home = homedir()
  const roots = [
    resolve(home, 'Library', 'Application Support', 'agent-desktop'),
    resolve(home, '.local', 'share', 'agent-desktop'),
    resolve(home, 'AppData', 'Roaming', 'agent-desktop'),
    resolve(tmpdir(), 'agent-desktop')
  ]
  return roots
}

/**
 * True if path is the default bridge file or under an allowlisted root.
 * Env override AGENT_DESKTOP_EVENTS must still sit under home or tmp.
 */
export function isAllowedWatchPath(filePath: string): boolean {
  const resolved = resolve(filePath)
  const defaultPath = resolve(agentDesktopEventsPath())
  if (resolved === defaultPath) return true

  const home = resolve(homedir())
  const tmp = resolve(tmpdir())
  if (process.env.AGENT_DESKTOP_EVENTS) {
    return underRoot(resolved, home) || underRoot(resolved, tmp)
  }

  return allowedWatchRoots().some((root) => underRoot(resolved, root))
}
