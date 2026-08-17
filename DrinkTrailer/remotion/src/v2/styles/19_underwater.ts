import type {TrailerStyleConfig} from '../config/types';

/** 19 — Underwater: Tiefblau, Bläschen-Glow (Bloom), langsame Tauchfahrt. */
export const style: TrailerStyleConfig = {
  id: 19,
  slug: 'underwater',
  displayName: 'Underwater',
  durationSec: 20,
  track: 'deep_ambient',
  trackFallback: 'clean',
  musicVolume: 0.85,
  palette: {bg: '#04121F', ink: '#D8F2FF', accent: '#37C8F0', accent2: '#1A5A7A'},
  fontPreset: 'clean',
  gradePreset: 'cool',
  effects: ['grain', 'vignette', 'bloom'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'hero', assetKey: 'bubblesUnderwater', text: 'Tauch kurz *ab*', beats: 9, transition: 'cut'},
    {kind: 'macro', assetKey: 'poolSplash', text: 'Kühler als kühl', beats: 7},
    {kind: 'type', text: 'TIEF|ERFRISCHEND', beats: 6, variant: 'lines'},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Tauch kurz ab.',
    mid: ['Isotonisch', 'Hydration with Benefits'],
    cta: 'Auftauchen? *Später.*',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 2, volume: 0.6},
      {name: 'fizz', beat: 12, volume: 0.45},
    ],
    onSceneCut: null,
  },
};
