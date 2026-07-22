import { contextBridge, ipcRenderer } from 'electron'
import { IpcChannels } from '@shared/ipc'
import type { SessionsSnapshot } from '@shared/types'

export type IslandMode = 'collapsed' | 'expanded'

const api = {
  getSessions: (): Promise<SessionsSnapshot> =>
    ipcRenderer.invoke(IpcChannels.getSessions),
  getBridgePath: (): Promise<string> => ipcRenderer.invoke(IpcChannels.getBridgePath),
  getIslandMode: (): Promise<IslandMode> =>
    ipcRenderer.invoke(IpcChannels.getIslandMode),
  setIslandMode: (mode: IslandMode): Promise<IslandMode> =>
    ipcRenderer.invoke(IpcChannels.setIslandMode, mode),
  toggleIsland: (): Promise<IslandMode> =>
    ipcRenderer.invoke(IpcChannels.toggleIsland),
  onSessionsUpdated: (callback: (snapshot: SessionsSnapshot) => void): (() => void) => {
    const handler = (_event: Electron.IpcRendererEvent, snapshot: SessionsSnapshot): void => {
      callback(snapshot)
    }
    ipcRenderer.on(IpcChannels.sessionsUpdated, handler)
    return () => {
      ipcRenderer.removeListener(IpcChannels.sessionsUpdated, handler)
    }
  },
  onIslandMode: (callback: (mode: IslandMode) => void): (() => void) => {
    const handler = (_event: Electron.IpcRendererEvent, mode: IslandMode): void => {
      callback(mode)
    }
    ipcRenderer.on(IpcChannels.islandMode, handler)
    return () => {
      ipcRenderer.removeListener(IpcChannels.islandMode, handler)
    }
  }
}

contextBridge.exposeInMainWorld('sessionMonitor', api)

export type SessionMonitorApi = typeof api
