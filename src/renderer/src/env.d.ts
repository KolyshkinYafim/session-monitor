import type { SessionMonitorApi } from '../../preload/index'

declare global {
  interface Window {
    sessionMonitor: SessionMonitorApi
  }
}

export {}
