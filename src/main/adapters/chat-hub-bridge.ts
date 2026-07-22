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
import type { SessionEvent } from '@shared/types'
import { agentDesktopEventsPath } from '@shared/bridge-path'
import { sessionBus } from '../session/bus'
import { sessionRegistry } from '../session/registry'

const POLL_MS = 750

function parseSessionEvent(line: string): SessionEvent | null {
  const trimmed = line.trim()
  if (!trimmed) return null
  try {
    const obj = JSON.parse(trimmed) as { type?: string }
    if (!obj || typeof obj.type !== 'string') return null
    if (!obj.type.startsWith('session.')) return null
    return obj as SessionEvent
  } catch {
    return null
  }
}

/**
 * Tails Chat Hub's append-only SessionEvent JSONL.
 * Safe if Hub is not running (empty/missing file).
 */
export class ChatHubBridgeAdapter {
  private readonly filePath: string
  private offset = 0
  private buffer = ''
  private watcher: FSWatcher | null = null
  private pollTimer: ReturnType<typeof setInterval> | null = null
  private reading = false
  private stopped = true
  /** Cold replay has no live Hub process — never restore "running". */
  private replaying = false

  constructor(filePath = agentDesktopEventsPath()) {
    this.filePath = filePath
  }

  get path(): string {
    return this.filePath
  }

  start(): void {
    if (!this.stopped) return
    this.stopped = false

    try {
      mkdirSync(dirname(this.filePath), { recursive: true })
      if (!existsSync(this.filePath)) {
        writeFileSync(this.filePath, '', 'utf8')
      }
    } catch (err) {
      console.error('[chat-hub-bridge] ensure file failed', err)
      return
    }

    // Replay existing events without OS notifications, then live-tail.
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
        // Truncated / rotated
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
    if (event.type === 'session.upsert' && event.session.status === 'running') {
      return {
        ...event,
        session: { ...event.session, status: 'idle' }
      }
    }
    return event
  }
}
