import type {TrailerStyleConfig} from '../config/types';

/** 07 — Lofi Morning: warmes Morgenlicht, Light Leaks, entspannter Start in den Tag. */
export const style: TrailerStyleConfig = {
  id: 7,
  slug: 'lofi_morning',
  displayName: 'Lofi Morning',
  durationSec: 19,
  track: 'lofi_chill',
  trackFallback: 'clean',
  musicVolume: 0.85,
  palette: {bg: '#F6EEE3', ink: '#3A3129', accent: '#D9A05B', accent2: '#B7C9A8'},
  fontPreset: 'clean',
  gradePreset: 'warm',
  effects: ['grain', 'light_leak', 'progress_dots'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'lifestyle', assetKey: 'sunriseRun', text: 'Erst laufen. Dann alles andere.', beats: 6, transition: 'cut'},
    {kind: 'macro', assetKey: 'pourGlass', text: 'Langsam eingeschenkt', beats: 5},
    {kind: 'hero', assetKey: 'studyDesk', text: 'Sanfter *Start*', beats: 5},
    {kind: 'quote', text: 'Der Morgen gehört dir. — EARLY', beats: 6},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Sanfter Start.',
    mid: ['Hydration with Benefits', 'Vitamine + Elektrolyte'],
    cta: 'Morgen beginnt *heute*',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 3, volume: 0.5},
      {name: 'sparkle_pop', beat: 14, volume: 0.4},
    ],
    onSceneCut: null,
  },
};
