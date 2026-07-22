export const IpcChannels = {
  getSessions: 'sessions:get',
  sessionsUpdated: 'sessions:updated',
  showWindow: 'window:show',
  getBridgePath: 'bridge:path',
  getIslandMode: 'island:get-mode',
  setIslandMode: 'island:set-mode',
  toggleIsland: 'island:toggle',
  islandMode: 'island:mode'
} as const
