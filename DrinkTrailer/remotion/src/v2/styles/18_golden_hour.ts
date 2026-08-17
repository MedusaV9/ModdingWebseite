import type {TrailerStyleConfig} from '../config/types';

/** 18 — Golden Hour: Abendsonne, Light Leaks, warmes Gold auf dunklem Amber. */
export const style: TrailerStyleConfig = {
  id: 18,
  slug: 'golden_hour',
  displayName: 'Golden Hour',
  durationSec: 20,
  track: 'golden_indie',
  trackFallback: 'clean',
  musicVolume: 0.9,
  palette: {bg: '#2A1E14', ink: '#FFE9C7', accent: '#FFB65C', accent2: '#E77F4F'},
  fontPreset: 'clean',
  gradePreset: 'warm',
  effects: ['light_leak', 'grain', 'vignette'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'lifestyle', assetKey: 'sunriseRun', text: 'Die beste Stunde des Tages', beats: 7, transition: 'cut'},
    {kind: 'hero', assetKey: 'picnic', text: 'Bleib noch *kurz*', beats: 6},
    {kind: 'macro', assetKey: 'pourGlass', text: 'Golden eingeschenkt', beats: 6},
    {kind: 'splash', assetKey: 'splashPeach', text: 'CHEERS.', beats: 5},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Die beste Stunde des Tages.',
    mid: ['Hydration with Benefits', 'Vitamine + Elektrolyte'],
    cta: 'Für *goldene* Momente',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 3, volume: 0.5},
      {name: 'sparkle_pop', beat: 19, volume: 0.5},
    ],
    onSceneCut: null,
  },
};
