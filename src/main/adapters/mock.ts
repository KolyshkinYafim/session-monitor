import type { SessionMeta, SessionStatus } from '@shared/types'
import { sessionBus } from '../session/bus'
import type { SessionAdapter } from './types'

const CYCLE: SessionStatus[] = ['running', 'waiting_input', 'running', 'done']
const CYCLE_MS = 4000

type MockSessionSeed = {
  id: string
  title: string
  provider: string
  cwd: string
  phaseOffset: number
}

const SEEDS: MockSessionSeed[] = [
  {
    id: 'mock-grok-1',
    title: 'Refactor auth middleware',
    provider: 'grok',
    cwd: '/Users/dev/projects/api',
    phaseOffset: 0
  },
  {
    id: 'mock-claude-1',
    title: 'Fix flaky e2e suite',
    provider: 'claude',
    cwd: '/Users/dev/projects/web',
    phaseOffset: 1
  },
  {
    id: 'mock-codex-1',
    title: 'Add session metrics',
    provider: 'codex',
    cwd: '/Users/dev/projects/monitor',
    phaseOffset: 2
  }
]

export class MockAdapter implements SessionAdapter {
  readonly id = 'mock'
  private timers: ReturnType<typeof setInterval>[] = []
  private phases = new Map<string, number>()

  start(): void {
    const now = Date.now()
    for (const seed of SEEDS) {
      const phase = seed.phaseOffset % CYCLE.length
      const status = CYCLE[phase]!
      this.phases.set(seed.id, phase)
      const session: SessionMeta = {
        id: seed.id,
        title: seed.title,
        provider: seed.provider,
        cwd: seed.cwd,
        status,
        createdAt: now - seed.phaseOffset * 60_000,
        updatedAt: now,
        lastEventAt: now,
        statusChangedAt: now,
        pending: null
      }
      sessionBus.emitEvent({ type: 'session.upsert', session })
    }

    for (const seed of SEEDS) {
      const timer = setInterval(() => this.advance(seed.id), CYCLE_MS)
      this.timers.push(timer)
    }
  }

  stop(): void {
    for (const timer of this.timers) clearInterval(timer)
    this.timers = []
  }

  private advance(id: string): void {
    const nextPhase = ((this.phases.get(id) ?? 0) + 1) % CYCLE.length
    this.phases.set(id, nextPhase)
    const status = CYCLE[nextPhase]!

    if (status === 'waiting_input') {
      sessionBus.emitEvent({
        type: 'session.question',
        id,
        requestId: `q-${id}-${Date.now()}`,
        prompt: 'Continue with destructive change?',
        options: ['Allow', 'Deny']
      })
      return
    }

    if (status === 'done') {
      sessionBus.emitEvent({ type: 'session.status', id, status: 'done' })
      sessionBus.emitEvent({ type: 'session.ended', id, reason: 'done' })
      return
    }

    sessionBus.emitEvent({ type: 'session.status', id, status })
  }
}
