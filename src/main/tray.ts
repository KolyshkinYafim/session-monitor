import { BrowserWindow, Menu, Tray, app, nativeImage } from 'electron'

let tray: Tray | null = null

function trayIcon(): Electron.NativeImage {
  const size = 16
  const canvas = Buffer.alloc(size * size * 4)
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = x - 7.5
      const dy = y - 7.5
      const dist = Math.sqrt(dx * dx + dy * dy)
      const i = (y * size + x) * 4
      if (dist <= 6.5) {
        canvas[i] = 90
        canvas[i + 1] = 200
        canvas[i + 2] = 250
        canvas[i + 3] = dist <= 5.2 ? 255 : 180
      }
    }
  }
  return nativeImage.createFromBuffer(canvas, { width: size, height: size })
}

export function createTray(getMainWindow: () => BrowserWindow | null): Tray {
  if (tray) return tray

  tray = new Tray(trayIcon())
  tray.setToolTip('Session Monitor')
  updateTrayBadge(0)

  const show = (): void => {
    // getMainWindow side-effect expands island (see createTray caller)
    const win = getMainWindow()
    if (!win) return
    win.show()
    win.focus()
  }

  tray.on('click', show)
  tray.on('double-click', show)

  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Open Session Monitor', click: show },
      { type: 'separator' },
      {
        label: 'Quit',
        click: () => {
          app.quit()
        }
      }
    ])
  )

  return tray
}

export function updateTrayBadge(waitingCount: number): void {
  if (!tray) return
  if (process.platform === 'darwin') {
    tray.setTitle(waitingCount > 0 ? String(waitingCount) : '')
  } else {
    tray.setToolTip(
      waitingCount > 0
        ? `Session Monitor · ${waitingCount} waiting`
        : 'Session Monitor'
    )
  }

  // Dock is hidden for ambient island mode — badge stays on tray title only
}

export function destroyTray(): void {
  tray?.destroy()
  tray = null
}
