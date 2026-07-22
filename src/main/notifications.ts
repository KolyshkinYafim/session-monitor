import { Notification } from 'electron'
import type { SessionMeta, SessionStatus } from '@shared/types'

const titles: Record<SessionStatus, string> = {
  idle: 'Idle',
  running: 'Running',
  waiting_input: 'Needs input',
  error: 'Error',
  done: 'Done'
}

export function notifySessionStatus(session: SessionMeta, status: SessionStatus): void {
  if (!Notification.isSupported()) return
  if (status !== 'waiting_input' && status !== 'done' && status !== 'error') return

  const notification = new Notification({
    title: `${titles[status]} · ${session.provider}`,
    body: session.title,
    silent: false
  })
  notification.show()
}
