import type {TrailerStyleConfig} from '../config/types';

/** 12 — Macro Sensory: ASMR-Nahaufnahmen, Kondenswasser, langsame Luma-Fades. */
export const style: TrailerStyleConfig = {
  id: 12,
  slug: 'macro_sensory',
  displayName: 'Macro Sensory',
  durationSec: 20,
  track: 'asmr_texture',
  trackFallback: 'clean',
  musicVolume: 0.85,
  palette: {bg: '#101820', ink: '#EAF2F5', accent: '#7FD0E8', accent2: '#2E4A5A'},
  fontPreset: 'clean',
  gradePreset: 'cool',
  effects: ['grain', 'vignette'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'macro', assetKey: 'macroCondensation', text: 'Hörst du das?', beats: 8, transition: 'cut'},
    {kind: 'macro', assetKey: 'bubblesUnderwater', text: 'Tausend kleine Perlen', beats: 7},
    {kind: 'macro', assetKey: 'pourGlass', text: 'Eiskalt eingeschenkt', beats: 7},
    {kind: 'splash', assetKey: 'splashPeach', text: 'AHH.', beats: 4},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Ganz nah dran.',
    mid: ['Hydration with Benefits', 'Isotonisch'],
    cta: 'Zum *Reinhören* nah',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 1, volume: 0.65},
      {name: 'fizz', beat: 15, volume: 0.5},
      {name: 'sparkle_pop', beat: 22, volume: 0.5},
    ],
    onSceneCut: null,
  },
};
