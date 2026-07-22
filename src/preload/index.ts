import { contextBridge, ipcRenderer } from 'electron'
import { IpcChannels } from '@shared/ipc'
import type { SessionsSnapshot } from '@shared/types'

const api = {
  getSessions: (): Promise<SessionsSnapshot> =>
    ipcRenderer.invoke(IpcChannels.getSessions),
  getBridgePath: (): Promise<string> => ipcRenderer.invoke(IpcChannels.getBridgePath),
  onSessionsUpdated: (callback: (snapshot: SessionsSnapshot) => void): (() => void) => {
    const handler = (_event: Electron.IpcRendererEvent, snapshot: SessionsSnapshot): void => {
      callback(snapshot)
    }
    ipcRenderer.on(IpcChannels.sessionsUpdated, handler)
    return () => {
      ipcRenderer.removeListener(IpcChannels.sessionsUpdated, handler)
    }
  }
}

contextBridge.exposeInMainWorld('sessionMonitor', api)

export type SessionMonitorApi = typeof api
