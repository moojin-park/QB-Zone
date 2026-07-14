export type ViewMode = 'auto' | 'classic' | 'wide';

export const VISUAL_CONFIG = {
  title: 'Pocket Vector',
  offenseTeam: 'Nova City Comets',
  defenseTeam: 'Iron Bay Phantoms',
  colors: {
    midnight: '#071526',
    navy: '#0b2340',
    turfDark: '#086f66',
    turfLight: '#19aa88',
    cyan: '#42e8ff',
    coral: '#ff5d73',
    violet: '#9b6cff',
    gold: '#ffd166',
    ice: '#effcff',
    ink: '#03101d',
  },
  field: {
    canonicalWidth: 1024,
    canonicalHeight: 768,
    horizonY: 232,
    nearGroundY: 895,
    farHalfWidthPx: 445,
    nearHalfWidthPx: 700,
    depthExponent: 2,
    farActorScale: 0.25,
    nearActorScale: 1,
    actorHeightPx: 300,
  },
} as const;
