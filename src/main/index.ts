import { BrowserWindow, app, ipcMain, screen } from 'electron'
import { ChatHubBridgeAdapter } from './adapters/chat-hub-bridge'
import { MockAdapter } from './adapters/mock'
import { AdapterHost } from './adapters/types'
import {
  createIslandWindow,
  reanchorIsland,
  setIslandMode,
  type IslandMode
} from './island'
import { notifySessionStatus } from './notifications'
import { sessionRegistry } from './session/registry'
import { createTray, destroyTray, updateTrayBadge } from './tray'
import { IpcChannels } from '@shared/ipc'
import type { SessionsSnapshot } from '@shared/types'

let islandWindow: BrowserWindow | null = null
let islandMode: IslandMode = 'collapsed'

const chatHubBridge = new ChatHubBridgeAdapter()
const adapterHost = new AdapterHost()
  .register(new MockAdapter())
  .register(chatHubBridge)

function getIsland(): BrowserWindow | null {
  return islandWindow
}

function broadcast(snapshot: SessionsSnapshot): void {
  updateTrayBadge(snapshot.waitingCount)
  for (const win of BrowserWindow.getAllWindows()) {
    win.webContents.send(IpcChannels.sessionsUpdated, snapshot)
  }
}

function applyMode(mode: IslandMode): void {
  islandMode = mode
  if (!islandWindow || islandWindow.isDestroyed()) return
  setIslandMode(islandWindow, mode)
  islandWindow.webContents.send(IpcChannels.islandMode, mode)
}

function registerIpc(): void {
  ipcMain.removeHandler(IpcChannels.getSessions)
  ipcMain.removeHandler(IpcChannels.getBridgePath)
  ipcMain.removeHandler(IpcChannels.getIslandMode)
  ipcMain.removeHandler(IpcChannels.setIslandMode)
  ipcMain.removeHandler(IpcChannels.toggleIsland)

  ipcMain.handle(IpcChannels.getSessions, () => sessionRegistry.snapshot())
  ipcMain.handle(IpcChannels.getBridgePath, () => chatHubBridge.path)
  ipcMain.handle(IpcChannels.getIslandMode, () => islandMode)
  ipcMain.handle(IpcChannels.setIslandMode, (_e, mode: IslandMode) => {
    if (mode !== 'collapsed' && mode !== 'expanded') return islandMode
    applyMode(mode)
    return islandMode
  })
  ipcMain.handle(IpcChannels.toggleIsland, () => {
    applyMode(islandMode === 'collapsed' ? 'expanded' : 'collapsed')
    return islandMode
  })
}

app.whenReady().then(() => {
  // Ambient app: no Dock document window — island + menu bar tray
  if (process.platform === 'darwin' && app.dock) {
    app.dock.hide()
  }

  registerIpc()

  sessionRegistry.start({
    onNotify: (session, status) => {
      notifySessionStatus(session, status)
    }
  })

  sessionRegistry.subscribe((snapshot) => {
    broadcast(snapshot)
  })

  islandWindow = createIslandWindow()
  islandWindow.on('closed', () => {
    islandWindow = null
  })
  islandWindow.on('blur', () => {
    // Ambient HUD: click outside collapses (skip if already collapsed)
    if (islandMode === 'expanded') {
      // slight delay so pill/toggle clicks don't immediately collapse
      setTimeout(() => {
        if (
          islandWindow &&
          !islandWindow.isDestroyed() &&
          !islandWindow.isFocused() &&
          islandMode === 'expanded'
        ) {
          applyMode('collapsed')
        }
      }, 120)
    }
  })

  createTray(() => {
    const win = getIsland()
    if (!win) return null
    applyMode('expanded')
    return win
  })

  adapterHost.startAll()

  screen.on('display-metrics-changed', () => {
    if (islandWindow && !islandWindow.isDestroyed()) {
      reanchorIsland(islandWindow, islandMode)
    }
  })

  app.on('activate', () => {
    if (!islandWindow || islandWindow.isDestroyed()) {
      islandWindow = createIslandWindow()
    }
    applyMode('expanded')
  })
})

app.on('window-all-closed', () => {
  // Keep running in tray/island on macOS
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

app.on('before-quit', () => {
  adapterHost.stopAll()
  sessionRegistry.stop()
  destroyTray()
})
