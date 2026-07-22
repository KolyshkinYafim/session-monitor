export interface SessionAdapter {
  readonly id: string
  start(): void
  stop(): void
}

export class AdapterHost {
  private readonly adapters: SessionAdapter[] = []

  register(adapter: SessionAdapter): this {
    this.adapters.push(adapter)
    return this
  }

  startAll(): void {
    for (const adapter of this.adapters) {
      try {
        adapter.start()
      } catch (err) {
        console.error(`[adapter-host] start failed: ${adapter.id}`, err)
      }
    }
  }

  stopAll(): void {
    for (const adapter of this.adapters) {
      try {
        adapter.stop()
      } catch (err) {
        console.error(`[adapter-host] stop failed: ${adapter.id}`, err)
      }
    }
  }

  get(id: string): SessionAdapter | undefined {
    return this.adapters.find((a) => a.id === id)
  }

  list(): readonly SessionAdapter[] {
    return this.adapters
  }
}
