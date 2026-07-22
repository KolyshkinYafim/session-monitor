import { app } from 'electron'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import type { PendingInteraction, SessionMeta, SessionStatus } from '@shared/types'

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

function isPending(value: unknown): value is PendingInteraction {
  if (!value || typeof value !== 'object') return false
  const p = value as PendingInteraction
  if (p.kind === 'permission') {
    return typeof p.requestId === 'string' && typeof p.summary === 'string'
  }
  if (p.kind === 'question') {
    return typeof p.requestId === 'string' && typeof p.prompt === 'string'
  }
  return false
}

function normalizeMeta(value: unknown): SessionMeta | null {
  if (!value || typeof value !== 'object') return null
  const s = value as Partial<SessionMeta>
  if (
    typeof s.id !== 'string' ||
    s.id.length === 0 ||
    typeof s.title !== 'string' ||
    typeof s.provider !== 'string' ||
    typeof s.cwd !== 'string' ||
    typeof s.status !== 'string' ||
    !STATUSES.has(s.status as SessionStatus) ||
    typeof s.updatedAt !== 'number' ||
    typeof s.createdAt !== 'number'
  ) {
    return null
  }

  const updatedAt = s.updatedAt
  const meta: SessionMeta = {
    id: s.id,
    title: s.title,
    provider: s.provider,
    cwd: s.cwd,
    status: s.status as SessionStatus,
    updatedAt,
    createdAt: s.createdAt,
    lastEventAt: typeof s.lastEventAt === 'number' ? s.lastEventAt : updatedAt,
    statusChangedAt:
      typeof s.statusChangedAt === 'number' ? s.statusChangedAt : updatedAt,
    pending: s.pending == null ? null : isPending(s.pending) ? s.pending : null
  }
  return meta
}

/** Live statuses are not trustworthy without a producer after restart. */
export function hydrateSession(session: SessionMeta): SessionMeta {
  if (!LIVE_STATUSES.has(session.status)) return session
  return {
    ...session,
    status: 'idle',
    pending: null,
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
    return data.sessions
      .map(normalizeMeta)
      .filter((s): s is SessionMeta => s != null)
      .map(hydrateSession)
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
