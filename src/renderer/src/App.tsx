import { useEffect, useMemo, useState } from 'react'
import type { SessionsSnapshot } from '@shared/types'
import type { IslandMode } from '../../preload/index'
import { SessionList } from './components/SessionList'

const empty: SessionsSnapshot = { sessions: [], waitingCount: 0 }

function statusCounts(sessions: SessionsSnapshot['sessions']) {
  let running = 0
  let waiting = 0
  let error = 0
  for (const s of sessions) {
    if (s.status === 'running') running += 1
    if (s.status === 'waiting_input') waiting += 1
    if (s.status === 'error') error += 1
  }
  return { running, waiting, error }
}

export function App(): React.JSX.Element {
  const [snapshot, setSnapshot] = useState<SessionsSnapshot>(empty)
  const [mode, setMode] = useState<IslandMode>('collapsed')

  useEffect(() => {
    let unsubSessions: (() => void) | undefined
    let unsubMode: (() => void) | undefined
    void window.sessionMonitor.getSessions().then(setSnapshot)
    void window.sessionMonitor.getIslandMode().then(setMode)
    unsubSessions = window.sessionMonitor.onSessionsUpdated(setSnapshot)
    unsubMode = window.sessionMonitor.onIslandMode(setMode)
    return () => {
      unsubSessions?.()
      unsubMode?.()
    }
  }, [])

  const counts = useMemo(
    () => statusCounts(snapshot.sessions),
    [snapshot.sessions]
  )

  const totalLive = counts.running + counts.waiting + counts.error
  const badge =
    snapshot.waitingCount > 0
      ? snapshot.waitingCount
      : totalLive > 0
        ? totalLive
        : snapshot.sessions.length

  async function toggle(): Promise<void> {
    const next = await window.sessionMonitor.toggleIsland()
    setMode(next)
  }

  async function collapse(): Promise<void> {
    const next = await window.sessionMonitor.setIslandMode('collapsed')
    setMode(next)
  }

  if (mode === 'collapsed') {
    return (
      <div className="island-root collapsed">
        <button
          type="button"
          className={`island-pill ${snapshot.waitingCount > 0 ? 'alert' : ''} ${counts.running > 0 ? 'live' : ''}`}
          onClick={() => void toggle()}
          title="Session Monitor — click to expand"
        >
          <span className="pill-icons" aria-hidden>
            <span className={`dot running ${counts.running ? 'on' : ''}`} />
            <span className={`dot waiting ${counts.waiting ? 'on' : ''}`} />
            <span className={`dot error ${counts.error ? 'on' : ''}`} />
          </span>
          <span className="pill-divider" aria-hidden />
          <span className="pill-count">{badge}</span>
          {counts.running > 0 ? (
            <span className="pill-label">Working</span>
          ) : snapshot.waitingCount > 0 ? (
            <span className="pill-label">Waiting</span>
          ) : (
            <span className="pill-label muted">Agents</span>
          )}
        </button>
      </div>
    )
  }

  return (
    <div className="island-root expanded">
      <div className="island-panel">
        <header className="island-header">
          <button
            type="button"
            className="island-pill mini"
            onClick={() => void collapse()}
            title="Collapse"
          >
            <span className="pill-icons" aria-hidden>
              <span className={`dot running ${counts.running ? 'on' : ''}`} />
              <span className={`dot waiting ${counts.waiting ? 'on' : ''}`} />
            </span>
            <span className="pill-count">{badge}</span>
          </button>
          <div className="island-title">
            <strong>Sessions</strong>
            <span>
              {counts.running} work · {counts.waiting} wait
            </span>
          </div>
          <button
            type="button"
            className="collapse-btn"
            onClick={() => void collapse()}
            aria-label="Collapse island"
          >
            ⌃
          </button>
        </header>
        <SessionList sessions={snapshot.sessions} />
      </div>
    </div>
  )
}
