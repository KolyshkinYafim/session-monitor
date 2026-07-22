import { app } from 'electron'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import type { SessionMeta } from '@shared/types'

type StoreFile = {
  sessions: SessionMeta[]
}

function storePath(): string {
  return join(app.getPath('userData'), 'sessions.json')
}

export function loadSessions(): SessionMeta[] {
  const path = storePath()
  if (!existsSync(path)) return []
  try {
    const raw = readFileSync(path, 'utf8')
    const data = JSON.parse(raw) as StoreFile
    if (!Array.isArray(data.sessions)) return []
    return data.sessions
  } catch {
    return []
  }
}

export function saveSessions(sessions: SessionMeta[]): void {
  const path = storePath()
  mkdirSync(dirname(path), { recursive: true })
  const payload: StoreFile = { sessions }
  writeFileSync(path, JSON.stringify(payload, null, 2), 'utf8')
}
