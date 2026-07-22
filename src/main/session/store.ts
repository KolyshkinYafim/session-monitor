import { app } from 'electron'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import type { SessionMeta, SessionStatus } from '@shared/types'

type StoreFile = {
  sessions: SessionMeta[]
}

const STATUSES = new Set<SessionStatus>([
  'idle',
  'running',
  'waiting_input',
  'error',
  'done'
])

const LIVE_STATUSES = new Set<SessionStatus>(['running', 'waiting_input'])

function storePath(): string {
  return join(app.getPath('userData'), 'sessions.json')
}

function isSessionMeta(value: unknown): value is SessionMeta {
  if (!value || typeof value !== 'object') return false
  const s = value as Partial<SessionMeta>
  return (
    typeof s.id === 'string' &&
    s.id.length > 0 &&
    typeof s.title === 'string' &&
    typeof s.provider === 'string' &&
    typeof s.cwd === 'string' &&
    typeof s.status === 'string' &&
    STATUSES.has(s.status as SessionStatus) &&
    typeof s.updatedAt === 'number' &&
    typeof s.createdAt === 'number'
  )
}

/** Live statuses are not trustworthy without a producer after restart. */
export function hydrateSession(session: SessionMeta): SessionMeta {
  if (!LIVE_STATUSES.has(session.status)) return session
  return {
    ...session,
    status: 'idle',
    updatedAt: session.updatedAt
  }
}

export function loadSessions(): SessionMeta[] {
  const path = storePath()
  if (!existsSync(path)) return []
  try {
    const raw = readFileSync(path, 'utf8')
    const data = JSON.parse(raw) as StoreFile
    if (!Array.isArray(data.sessions)) return []
    return data.sessions.filter(isSessionMeta).map(hydrateSession)
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
