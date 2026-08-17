import type {TrailerStyleConfig} from '../config/types';

/** 30 — Zoom Through: ein einziger endloser Szene-in-Szene-Zoom bis zur Copy. */
export const style: TrailerStyleConfig = {
  id: 30,
  slug: 'zoom_through',
  displayName: 'Zoom Through',
  durationSec: 17,
  track: 'bass_tunnel',
  trackFallback: 'hype',
  palette: {bg: '#0D0D12', ink: '#F2EFFF', accent: '#8C5BFF', accent2: '#FF5B8C'},
  fontPreset: 'hype',
  gradePreset: 'cool',
  effects: ['chromatic', 'grain', 'vignette'],
  defaultTransition: 'cut',
  structure: [
    {kind: 'zoomthrough', assetKeys: ['heroPeach', 'macroCondensation', 'clubNeon', 'poolSplash'], text: 'IMMER *TIEFER*', beats: 24},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'IMMER TIEFER.',
    mid: ['SPARKLING VITAMIN DRINK'],
    cta: 'Am *Grund* wartet Geschmack',
  },
  sfxPlan: {
    cues: [
      {name: 'riser', beat: 0, volume: 0.55},
      {name: 'whoosh', beat: 6, volume: 0.5},
      {name: 'whoosh', beat: 12, volume: 0.5},
      {name: 'whoosh', beat: 18, volume: 0.5},
      {name: 'impact_1', beat: 24, volume: 0.85},
    ],
    onSceneCut: null,
  },
};
