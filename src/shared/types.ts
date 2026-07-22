export type SessionStatus = 'idle' | 'running' | 'waiting_input' | 'error' | 'done'

export type PendingInteraction =
  | { kind: 'permission'; requestId: string; summary: string }
  | { kind: 'question'; requestId: string; prompt: string; options?: string[] }

export type SessionMeta = {
  id: string
  title: string
  provider: string
  cwd: string
  status: SessionStatus
  updatedAt: number
  createdAt: number
  /** Last bus event time (liveness). */
  lastEventAt: number
  /** When status last changed (UI duration). */
  statusChangedAt: number
  pending?: PendingInteraction | null
}

export type SessionEvent =
  | { type: 'session.upsert'; session: SessionMeta }
  | { type: 'session.status'; id: string; status: SessionStatus }
  | { type: 'session.permission'; id: string; requestId: string; summary: string }
  | {
      type: 'session.question'
      id: string
      requestId: string
      prompt: string
      options?: string[]
    }
  | {
      type: 'session.message'
      id: string
      role: 'user' | 'assistant' | 'system'
      preview: string
    }
  | { type: 'session.ended'; id: string; reason: 'done' | 'error' | 'killed' }

export type SessionsSnapshot = {
  sessions: SessionMeta[]
  waitingCount: number
}
