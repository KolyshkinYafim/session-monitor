import { BrowserWindow, app, ipcMain } from 'electron'
import { join } from 'node:path'
import { MockAdapter } from './adapters/mock'
import { notifySessionStatus } from './notifications'
import { sessionRegistry } from './session/registry'
import { createTray, destroyTray, updateTrayBadge } from './tray'
import { IpcChannels } from '@shared/ipc'
import type { SessionsSnapshot } from '@shared/types'

let mainWindow: BrowserWindow | null = null
const mockAdapter = new MockAdapter()

function createWindow(): BrowserWindow {
  const win = new BrowserWindow({
    width: 420,
    height: 560,
    minWidth: 360,
    minHeight: 400,
    show: false,
    title: 'Session Monitor',
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    trafficLightPosition: { x: 12, y: 12 },
    backgroundColor: '#0f1115',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })

  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  win.webContents.on('will-navigate', (event, url) => {
    const allowed =
      process.env.ELECTRON_RENDERER_URL != null
        ? url.startsWith(process.env.ELECTRON_RENDERER_URL)
        : url.startsWith('file://')
    if (!allowed) event.preventDefault()
  })

  win.on('ready-to-show', () => {
    win.show()
  })

  win.on('closed', () => {
    mainWindow = null
  })

  if (process.env.ELECTRON_RENDERER_URL) {
    void win.loadURL(process.env.ELECTRON_RENDERER_URL)
  } else {
    void win.loadFile(join(__dirname, '../renderer/index.html'))
  }

  return win
}

function broadcast(snapshot: SessionsSnapshot): void {
  updateTrayBadge(snapshot.waitingCount)
  for (const win of BrowserWindow.getAllWindows()) {
    win.webContents.send(IpcChannels.sessionsUpdated, snapshot)
  }
}

function registerIpc(): void {
  ipcMain.removeHandler(IpcChannels.getSessions)
  ipcMain.handle(IpcChannels.getSessions, () => sessionRegistry.snapshot())
}

app.whenReady().then(() => {
  registerIpc()

  sessionRegistry.start({
    onNotify: (session, status) => {
      notifySessionStatus(session, status)
    }
  })

  sessionRegistry.subscribe((snapshot) => {
    broadcast(snapshot)
  })

  mainWindow = createWindow()
  createTray(() => mainWindow)
  mockAdapter.start()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      mainWindow = createWindow()
    } else {
      mainWindow?.show()
    }
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

app.on('before-quit', () => {
  mockAdapter.stop()
  sessionRegistry.stop()
  destroyTray()
})
