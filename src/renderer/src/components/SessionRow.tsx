import type { SessionMeta, SessionStatus } from '@shared/types'

type Props = {
  session: SessionMeta
}

const statusLabel: Record<SessionStatus, string> = {
  idle: 'idle',
  running: 'running',
  waiting_input: 'waiting',
  error: 'error',
  done: 'done'
}

function formatDuration(ms: number): string {
  const sec = Math.floor(Math.max(0, ms) / 1000)
  if (sec < 60) return `${sec}s`
  const min = Math.floor(sec / 60)
  if (min < 60) return `${min}m`
  const hr = Math.floor(min / 60)
  return `${hr}h ${min % 60}m`
}

function shortPath(cwd: string): string {
  if (!cwd) return '—'
  const parts = cwd.split('/').filter(Boolean)
  if (parts.length <= 2) return cwd
  return `…/${parts.slice(-2).join('/')}`
}

function pendingText(session: SessionMeta): string | null {
  if (!session.pending) return null
  if (session.pending.kind === 'permission') return session.pending.summary
  return session.pending.prompt
}

export function SessionRow({ session }: Props): React.JSX.Element {
  const sinceStatus = Date.now() - (session.statusChangedAt || session.updatedAt)
  const pending = pendingText(session)

  return (
    <li className={`session-row status-${session.status}`}>
      <div className="session-main">
        <div className="session-title-row">
          <span className="session-title">{session.title}</span>
          <span className={`status-pill status-${session.status}`}>
            {statusLabel[session.status]}
          </span>
        </div>
        <div className="session-meta">
          <span className="provider">{session.provider}</span>
          <span className="dot">·</span>
          <span className="cwd" title={session.cwd || undefined}>
            {shortPath(session.cwd)}
          </span>
          <span className="dot">·</span>
          <span className="duration" title="Time in current status">
            {formatDuration(sinceStatus)}
          </span>
        </div>
        {pending ? (
          <p className="session-pending" title={pending}>
            {pending}
          </p>
        ) : null}
      </div>
    </li>
  )
}
