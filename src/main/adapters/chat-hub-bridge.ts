import {
  closeSync,
  existsSync,
  mkdirSync,
  openSync,
  readSync,
  statSync,
  watch,
  writeFileSync,
  type FSWatcher
} from 'node:fs'
import { dirname } from 'node:path'
import type { SessionEvent, SessionMeta, SessionStatus } from '@shared/types'
import { agentDesktopEventsPath } from '@shared/bridge-path'
import { isAllowedWatchPath } from '../security/paths'
import { sessionBus } from '../session/bus'
import { sessionRegistry } from '../session/registry'
import type { SessionAdapter } from './types'

const POLL_MS = 750
const STATUSES = new Set<SessionStatus>([
  'idle',
  'running',
  'waiting_input',
  'error',
  'done'
])

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

function parseSessionEvent(line: string): SessionEvent | null {
  const trimmed = line.trim()
  if (!trimmed) return null
  try {
    const obj = JSON.parse(trimmed) as Record<string, unknown>
    if (!obj || typeof obj.type !== 'string' || !obj.type.startsWith('session.')) {
      return null
    }

    switch (obj.type) {
      case 'session.upsert': {
        if (!isSessionMeta(obj.session)) return null
        const raw = obj.session
        const now = Date.now()
        const session: SessionMeta = {
          ...raw,
          lastEventAt: typeof raw.lastEventAt === 'number' ? raw.lastEventAt : now,
          statusChangedAt:
            typeof raw.statusChangedAt === 'number' ? raw.statusChangedAt : now,
          pending: raw.pending ?? null
        }
        return { type: 'session.upsert', session }
      }
      case 'session.status':
        if (typeof obj.id !== 'string' || !STATUSES.has(obj.status as SessionStatus)) {
          return null
        }
        return { type: 'session.status', id: obj.id, status: obj.status as SessionStatus }
      case 'session.permission':
        if (
          typeof obj.id !== 'string' ||
          typeof obj.requestId !== 'string' ||
          typeof obj.summary !== 'string'
        ) {
          return null
        }
        return {
          type: 'session.permission',
          id: obj.id,
          requestId: obj.requestId,
          summary: obj.summary
        }
      case 'session.question':
        if (
          typeof obj.id !== 'string' ||
          typeof obj.requestId !== 'string' ||
          typeof obj.prompt !== 'string'
        ) {
          return null
        }
        return {
          type: 'session.question',
          id: obj.id,
          requestId: obj.requestId,
          prompt: obj.prompt,
          options: Array.isArray(obj.options)
            ? obj.options.filter((o): o is string => typeof o === 'string')
            : undefined
        }
      case 'session.message':
        if (
          typeof obj.id !== 'string' ||
          (obj.role !== 'user' && obj.role !== 'assistant' && obj.role !== 'system') ||
          typeof obj.preview !== 'string'
        ) {
          return null
        }
        return {
          type: 'session.message',
          id: obj.id,
          role: obj.role,
          preview: obj.preview
        }
      case 'session.ended':
        if (
          typeof obj.id !== 'string' ||
          (obj.reason !== 'done' && obj.reason !== 'error' && obj.reason !== 'killed')
        ) {
          return null
        }
        return { type: 'session.ended', id: obj.id, reason: obj.reason }
      default:
        return null
    }
  } catch {
    return null
  }
}

/** Tails Chat Hub's append-only SessionEvent JSONL. Safe if Hub is absent. */
export class ChatHubBridgeAdapter implements SessionAdapter {
  readonly id = 'chat-hub-bridge'
  private readonly filePath: string
  private offset = 0
  private buffer = ''
  private watcher: FSWatcher | null = null
  private pollTimer: ReturnType<typeof setInterval> | null = null
  private reading = false
  private stopped = true
  private replaying = false

  constructor(filePath = agentDesktopEventsPath()) {
    this.filePath = filePath
  }

  get path(): string {
    return this.filePath
  }

  start(): void {
    if (!this.stopped) return

    if (!isAllowedWatchPath(this.filePath)) {
      console.error('[chat-hub-bridge] path not allowlisted:', this.filePath)
      return
    }

    this.stopped = false

    try {
      mkdirSync(dirname(this.filePath), { recursive: true })
      if (!existsSync(this.filePath)) {
        writeFileSync(this.filePath, '', 'utf8')
      }
    } catch (err) {
      console.error('[chat-hub-bridge] ensure file failed', err)
      this.stopped = true
      return
    }

    sessionRegistry.setSuppressNotify(true)
    this.replaying = true
    this.offset = 0
    this.buffer = ''
    this.drain()
    this.replaying = false
    sessionRegistry.setSuppressNotify(false)

    try {
      this.watcher = watch(this.filePath, () => {
        this.drain()
      })
      this.watcher.on('error', (err) => {
        console.error('[chat-hub-bridge] watch error', err)
      })
    } catch (err) {
      console.error('[chat-hub-bridge] watch failed; poll only', err)
    }

    this.pollTimer = setInterval(() => this.drain(), POLL_MS)
  }

  stop(): void {
    this.stopped = true
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
    if (this.watcher) {
      this.watcher.close()
      this.watcher = null
    }
  }

  private drain(): void {
    if (this.stopped || this.reading) return
    this.reading = true
    try {
      if (!existsSync(this.filePath)) return

      const size = statSync(this.filePath).size
      if (size < this.offset) {
        this.offset = 0
        this.buffer = ''
      }
      if (size === this.offset) return

      const fd = openSync(this.filePath, 'r')
      try {
        const length = size - this.offset
        const buf = Buffer.alloc(length)
        readSync(fd, buf, 0, length, this.offset)
        this.offset = size
        this.buffer += buf.toString('utf8')
        this.flushLines()
      } finally {
        closeSync(fd)
      }
    } catch (err) {
      console.error('[chat-hub-bridge] read failed', err)
    } finally {
      this.reading = false
    }
  }

  private flushLines(): void {
    let idx = this.buffer.indexOf('\n')
    while (idx !== -1) {
      const line = this.buffer.slice(0, idx)
      this.buffer = this.buffer.slice(idx + 1)
      const event = parseSessionEvent(line)
      if (event) sessionBus.emitEvent(this.normalizeReplay(event))
      idx = this.buffer.indexOf('\n')
    }
  }

  private normalizeReplay(event: SessionEvent): SessionEvent {
    if (!this.replaying) return event
    if (event.type === 'session.status' && event.status === 'running') {
      return { ...event, status: 'idle' }
    }
    if (event.type === 'session.status' && event.status === 'waiting_input') {
      return { ...event, status: 'idle' }
    }
    if (
      event.type === 'session.upsert' &&
      (event.session.status === 'running' || event.session.status === 'waiting_input')
    ) {
      return {
        ...event,
        session: { ...event.session, status: 'idle', pending: null }
      }
    }
    if (event.type === 'session.permission' || event.type === 'session.question') {
      return { type: 'session.status', id: event.id, status: 'idle' }
    }
    return event
  }
}
