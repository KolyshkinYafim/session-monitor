import { EventEmitter } from 'node:events'
import type { SessionEvent } from '@shared/types'

class SessionEventBus {
  private emitter = new EventEmitter()

  emitEvent(event: SessionEvent): void {
    this.emitter.emit('event', event)
  }

  onEvent(listener: (event: SessionEvent) => void): () => void {
    this.emitter.on('event', listener)
    return () => {
      this.emitter.off('event', listener)
    }
  }
}

export const sessionBus = new SessionEventBus()
