import { useEffect, useState } from 'react'
import type { SessionsSnapshot } from '@shared/types'
import { SessionList } from './components/SessionList'

const empty: SessionsSnapshot = { sessions: [], waitingCount: 0 }

export function App(): React.JSX.Element {
  const [snapshot, setSnapshot] = useState<SessionsSnapshot>(empty)
  const [bridgePath, setBridgePath] = useState('')

  useEffect(() => {
    let unsub: (() => void) | undefined
    void window.sessionMonitor.getSessions().then(setSnapshot)
    void window.sessionMonitor.getBridgePath().then(setBridgePath)
    unsub = window.sessionMonitor.onSessionsUpdated(setSnapshot)
    return () => unsub?.()
  }, [])

  return (
    <div className="app">
      <header className="header">
        <div className="header-title">
          <h1>Session Monitor</h1>
          <p className="subtitle">Live agent sessions</p>
        </div>
        <div
          className={`badge ${snapshot.waitingCount > 0 ? 'badge-alert' : ''}`}
          title="Sessions waiting for input"
        >
          {snapshot.waitingCount}
        </div>
      </header>
      <SessionList sessions={snapshot.sessions} />
      {bridgePath ? (
        <footer className="bridge-footer" title={bridgePath}>
          <span>Chat Hub bridge</span>
          <code>{bridgePath}</code>
        </footer>
      ) : null}
    </div>
  )
}
