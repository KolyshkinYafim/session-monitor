import type { SessionEvent, SessionMeta, SessionStatus, SessionsSnapshot } from '@shared/types'
import { sessionBus } from './bus'
import { loadSessions, saveSessions } from './store'

type RegistryListener = (snapshot: SessionsSnapshot) => void

const NOTIFY_STATUSES: SessionStatus[] = ['waiting_input', 'done', 'error']

export class SessionRegistry {
  private sessions = new Map<string, SessionMeta>()
  private listeners = new Set<RegistryListener>()
  private onNotify: ((session: SessionMeta, status: SessionStatus) => void) | null = null
  private persistTimer: ReturnType<typeof setTimeout> | null = null
  private unsubBus: (() => void) | null = null

  start(options?: {
    onNotify?: (session: SessionMeta, status: SessionStatus) => void
  }): void {
    this.onNotify = options?.onNotify ?? null
    for (const session of loadSessions()) {
      this.sessions.set(session.id, session)
    }
    this.unsubBus = sessionBus.onEvent((event) => this.handleEvent(event))
  }

  stop(): void {
    this.unsubBus?.()
    this.unsubBus = null
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
        this.setStatus(event.id, status)
        break
      }
      case 'session.permission':
      case 'session.question':
        this.setStatus(event.id, 'waiting_input')
        break
      case 'session.message':
        this.touch(event.id)
        break
      default:
        break
    }
  }

  private upsert(session: SessionMeta): void {
    const prev = this.sessions.get(session.id)
    const next: SessionMeta = {
      ...session,
      updatedAt: session.updatedAt || Date.now()
    }
    this.sessions.set(session.id, next)
    if (!prev || prev.status !== next.status) {
      this.maybeNotify(next, next.status, prev?.status)
    }
    this.emitChange()
  }

  private setStatus(id: string, status: SessionStatus): void {
    const prev = this.sessions.get(id)
    if (!prev) return
    if (prev.status === status) {
      this.touch(id)
      return
    }
    const next: SessionMeta = {
      ...prev,
      status,
      updatedAt: Date.now()
    }
    this.sessions.set(id, next)
    this.maybeNotify(next, status, prev.status)
    this.emitChange()
  }

  private touch(id: string): void {
    const prev = this.sessions.get(id)
    if (!prev) return
    this.sessions.set(id, { ...prev, updatedAt: Date.now() })
    this.emitChange()
  }

  private maybeNotify(
    session: SessionMeta,
    status: SessionStatus,
    prevStatus?: SessionStatus
  ): void {
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
