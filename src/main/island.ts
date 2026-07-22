import { BrowserWindow, screen } from 'electron'
import { join } from 'node:path'

/** Collapsed Dynamic-Island style pill under the top center of the display. */
export const ISLAND_COLLAPSED = { width: 220, height: 44 } as const
/** Expanded dropdown panel under the same anchor. */
export const ISLAND_EXPANDED = { width: 360, height: 420 } as const

export type IslandMode = 'collapsed' | 'expanded'

/**
 * Floating ambient window — not a document window.
 * Anchored to the top-center of the primary display (menu bar / notch zone),
 * same class of surface as Vibe Island.
 */
export function createIslandWindow(): BrowserWindow {
  const win = new BrowserWindow({
    ...ISLAND_COLLAPSED,
    show: false,
    frame: false,
    transparent: true,
    hasShadow: true,
    resizable: false,
    maximizable: false,
    minimizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    focusable: true,
    movable: true,
    // panel-type stays above full-screen apps on macOS
    type: process.platform === 'darwin' ? 'panel' : 'normal',
    backgroundColor: '#00000000',
    title: 'Session Monitor',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })

  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  win.setAlwaysOnTop(true, 'screen-saver')
  // Slightly rounded hit-testing feels better for a pill
  if (process.platform === 'darwin') {
    win.setWindowButtonVisibility(false)
  }

  positionIsland(win, 'collapsed')

  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  win.webContents.on('will-navigate', (event, url) => {
    const allowed =
      process.env.ELECTRON_RENDERER_URL != null
        ? url.startsWith(process.env.ELECTRON_RENDERER_URL)
        : url.startsWith('file://')
    if (!allowed) event.preventDefault()
  })

  // Blur collapse is handled from main index so mode state stays in sync.

  if (process.env.ELECTRON_RENDERER_URL) {
    void win.loadURL(process.env.ELECTRON_RENDERER_URL)
  } else {
    void win.loadFile(join(__dirname, '../renderer/index.html'))
  }

  win.once('ready-to-show', () => {
    positionIsland(win, 'collapsed')
    win.showInactive()
  })

  return win
}

export function positionIsland(win: BrowserWindow, mode: IslandMode): void {
  const size = mode === 'expanded' ? ISLAND_EXPANDED : ISLAND_COLLAPSED
  const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint())
  // Use full bounds (not workArea) so we sit in the menu-bar / notch strip
  const { x: dx, y: dy, width: dw } = display.bounds
  const x = Math.round(dx + (dw - size.width) / 2)
  // Just under the top edge — like Vibe Island under the Dynamic Island / menubar
  const y = Math.round(dy + (process.platform === 'darwin' ? 8 : 4))

  win.setBounds({ x, y, width: size.width, height: size.height }, false)
}

export function setIslandMode(win: BrowserWindow, mode: IslandMode): void {
  positionIsland(win, mode)
  if (mode === 'expanded') {
    win.show()
    win.focus()
  } else {
    win.setAlwaysOnTop(true, 'screen-saver')
  }
}

export function reanchorIsland(win: BrowserWindow, mode: IslandMode): void {
  positionIsland(win, mode)
}
