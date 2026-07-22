import type { SessionMeta } from '@shared/types'
import { SessionRow } from './SessionRow'

type Props = {
  sessions: SessionMeta[]
}

export function SessionList({ sessions }: Props): React.JSX.Element {
  if (sessions.length === 0) {
    return (
      <div className="empty">
        <p>No sessions yet</p>
        <span>Adapters will appear here when agents start</span>
      </div>
    )
  }

  return (
    <ul className="session-list">
      {sessions.map((session) => (
        <SessionRow key={session.id} session={session} />
      ))}
    </ul>
  )
}
