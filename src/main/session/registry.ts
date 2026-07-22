import type {
  PendingInteraction,
  SessionEvent,
  SessionMeta,
  SessionStatus,
  SessionsSnapshot
} from '@shared/types'
import { sessionBus } from './bus'
import { loadSessions, saveSessions } from './store'

type RegistryListener = (snapshot: SessionsSnapshot) => void

const NOTIFY_STATUSES: SessionStatus[] = ['waiting_input', 'done', 'error']

/** If no bus event while running longer than this, demote to error. */
const STALE_RUNNING_MS = 5 * 60 * 1000
const STALE_CHECK_MS = 30_000

export class SessionRegistry {
  private sessions = new Map<string, SessionMeta>()
  private listeners = new Set<RegistryListener>()
  private onNotify: ((session: SessionMeta, status: SessionStatus) => void) | null = null
  private persistTimer: ReturnType<typeof setTimeout> | null = null
  private staleTimer: ReturnType<typeof setInterval> | null = null
  private unsubBus: (() => void) | null = null
  private suppressNotify = false

  start(options?: {
    onNotify?: (session: SessionMeta, status: SessionStatus) => void
    staleRunningMs?: number
  }): void {
    this.onNotify = options?.onNotify ?? null
    const staleMs = options?.staleRunningMs ?? STALE_RUNNING_MS

    for (const session of loadSessions()) {
      this.sessions.set(session.id, session)
    }
    this.unsubBus = sessionBus.onEvent((event) => this.handleEvent(event))
    this.staleTimer = setInterval(() => this.reapStaleRunning(staleMs), STALE_CHECK_MS)
  }

  setSuppressNotify(value: boolean): void {
    this.suppressNotify = value
  }

  stop(): void {
    this.unsubBus?.()
    this.unsubBus = null
    if (this.staleTimer) {
      clearInterval(this.staleTimer)
      this.staleTimer = null
    }
    if (this.persistTimer) {
      clearTimeout(this.persistTimer)
      this.persistTimer = null
    }
    this.flush()
  }

  subscribe(listener: RegistryListener): () => void {
    this.listeners.add(listener)
    listener(this.snapshot())
    return () => {
      this.listeners.delete(listener)
    }
  }

  snapshot(): SessionsSnapshot {
    const sessions = [...this.sessions.values()].sort((a, b) => b.updatedAt - a.updatedAt)
    const waitingCount = sessions.filter((s) => s.status === 'waiting_input').length
    return { sessions, waitingCount }
  }

  private handleEvent(event: SessionEvent): void {
    switch (event.type) {
      case 'session.upsert':
        this.upsert(event.session)
        break
      case 'session.status':
        this.setStatus(event.id, event.status)
        break
      case 'session.ended': {
        const status: SessionStatus = event.reason === 'error' ? 'error' : 'done'
        this.setStatus(event.id, status, { clearPending: true })
        break
      }
      case 'session.permission':
        this.setPending(event.id, {
          kind: 'permission',
          requestId: event.requestId,
          summary: event.summary
        })
        break
      case 'session.question':
        this.setPending(event.id, {
          kind: 'question',
          requestId: event.requestId,
          prompt: event.prompt,
          options: event.options
        })
        break
      case 'session.message':
        this.touch(event.id)
        break
      default:
        break
    }
  }

  private upsert(session: SessionMeta): void {
    const now = Date.now()
    const prev = this.sessions.get(session.id)
    const status = session.status
    const next: SessionMeta = {
      ...session,
      updatedAt: session.updatedAt || now,
      createdAt: session.createdAt || prev?.createdAt || now,
      lastEventAt: now,
      statusChangedAt:
        !prev || prev.status !== status
          ? session.statusChangedAt || now
          : prev.statusChangedAt,
      pending:
        status === 'waiting_input'
          ? (session.pending ?? prev?.pending ?? null)
          : null
    }
    this.sessions.set(session.id, next)
    if (!prev || prev.status !== next.status) {
      this.maybeNotify(next, next.status, prev?.status)
    }
    this.emitChange()
  }

  private ensureSession(id: string): SessionMeta {
    const existing = this.sessions.get(id)
    if (existing) return existing
    const now = Date.now()
    const skeleton: SessionMeta = {
      id,
      title: id,
      provider: 'unknown',
      cwd: '',
      status: 'idle',
      createdAt: now,
      updatedAt: now,
      lastEventAt: now,
      statusChangedAt: now,
      pending: null
    }
    this.sessions.set(id, skeleton)
    return skeleton
  }

  private setStatus(
    id: string,
    status: SessionStatus,
    opts?: { clearPending?: boolean }
  ): void {
    const prev = this.ensureSession(id)
    const now = Date.now()
    if (prev.status === status) {
      this.sessions.set(id, {
        ...prev,
        updatedAt: now,
        lastEventAt: now,
        pending: opts?.clearPending || status !== 'waiting_input' ? null : prev.pending
      })
      this.emitChange()
      return
    }
    const next: SessionMeta = {
      ...prev,
      status,
      updatedAt: now,
      lastEventAt: now,
      statusChangedAt: now,
      pending:
        opts?.clearPending || status !== 'waiting_input' ? null : prev.pending
    }
    this.sessions.set(id, next)
    this.maybeNotify(next, status, prev.status)
    this.emitChange()
  }

  private setPending(id: string, pending: PendingInteraction): void {
    const prev = this.ensureSession(id)
    const now = Date.now()
    const statusChanged = prev.status !== 'waiting_input'
    const next: SessionMeta = {
      ...prev,
      status: 'waiting_input',
      pending,
      updatedAt: now,
      lastEventAt: now,
      statusChangedAt: statusChanged ? now : prev.statusChangedAt
    }
    this.sessions.set(id, next)
    if (statusChanged) {
      this.maybeNotify(next, 'waiting_input', prev.status)
    }
    this.emitChange()
  }

  private touch(id: string): void {
    const prev = this.ensureSession(id)
    const now = Date.now()
    this.sessions.set(id, {
      ...prev,
      updatedAt: now,
      lastEventAt: now
    })
    this.emitChange()
  }

  private reapStaleRunning(staleMs: number): void {
    const now = Date.now()
    let changed = false
    for (const [id, session] of this.sessions) {
      if (session.status !== 'running') continue
      if (now - session.lastEventAt < staleMs) continue
      const next: SessionMeta = {
        ...session,
        status: 'error',
        pending: null,
        updatedAt: now,
        lastEventAt: now,
        statusChangedAt: now
      }
      this.sessions.set(id, next)
      this.maybeNotify(next, 'error', 'running')
      changed = true
    }
    if (changed) this.emitChange()
  }

  private maybeNotify(
    session: SessionMeta,
    status: SessionStatus,
    prevStatus?: SessionStatus
  ): void {
    if (this.suppressNotify) return
    if (prevStatus === status) return
    if (!NOTIFY_STATUSES.includes(status)) return
    this.onNotify?.(session, status)
  }

  private emitChange(): void {
    const snapshot = this.snapshot()
    for (const listener of this.listeners) {
      listener(snapshot)
    }
    this.schedulePersist()
  }

  private schedulePersist(): void {
    if (this.persistTimer) clearTimeout(this.persistTimer)
    this.persistTimer = setTimeout(() => this.flush(), 200)
  }

  private flush(): void {
    saveSessions(this.snapshot().sessions)
  }
}

export const sessionRegistry = new SessionRegistry()
