import type {TrailerStyleConfig} from '../config/types';

/** 32 — Luxury Serif: Gold-Duotone auf Tiefschwarz, Serifen-Understatement, Kino-Bars. */
export const style: TrailerStyleConfig = {
  id: 32,
  slug: 'luxury_serif',
  displayName: 'Luxury Serif',
  durationSec: 21,
  track: 'strings_noir',
  trackFallback: 'clean',
  musicVolume: 0.9,
  palette: {bg: '#0F0D0A', ink: '#EFE6D2', accent: '#C9A227', accent2: '#6E5A2E'},
  fontPreset: 'serif',
  gradePreset: 'bw_accent',
  effects: ['letterbox', 'vignette', 'grain'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'macro', assetKey: 'macroCondensation', text: 'Handwerk, eiskalt', beats: 8, transition: 'cut'},
    {kind: 'quote', text: 'Weniger, aber besser. — Hausregel', beats: 7},
    {kind: 'hero', assetKey: 'minimalFloat', text: 'Stille *Klasse*', beats: 7},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Stille Klasse.',
    mid: ['Hydration with Benefits'],
    cta: 'Der *feine* Unterschied',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 2, volume: 0.4},
      {name: 'sparkle_pop', beat: 15, volume: 0.35},
    ],
    onSceneCut: null,
  },
};
