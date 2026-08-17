import type {TrailerStyleConfig} from '../config/types';

/** 02 — Clean Air: helle Creme-Flächen, ruhige Luma-Fades, viel Weißraum. */
export const style: TrailerStyleConfig = {
  id: 2,
  slug: 'clean_air',
  displayName: 'Clean Air',
  durationSec: 18,
  track: 'air_breeze',
  trackFallback: 'clean',
  musicVolume: 0.9,
  palette: {bg: '#FAF3EC', ink: '#2A2A2A', accent: '#F2AC8F', accent2: '#CBD97A'},
  fontPreset: 'clean',
  gradePreset: 'none',
  effects: ['grain', 'progress_dots'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'hero', assetKey: 'minimalFloat', text: 'Leicht. Klar. Early.', beats: 6, transition: 'cut'},
    {kind: 'macro', assetKey: 'macroCondensation', text: 'Hydration with Benefits', beats: 5},
    {kind: 'lifestyle', assetKey: 'picnic', text: 'Für helle Tage', beats: 5},
    {kind: 'lineup', variant: 'grid', beats: 6},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Leicht. Klar. *Early*.',
    mid: ['Kalorienarm', 'Isotonisch', 'Vitamine + Elektrolyte'],
    cta: 'Probier alle *drei* Sorten',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 2, volume: 0.5},
      {name: 'sparkle_pop', beat: 12, volume: 0.5},
    ],
    onSceneCut: null,
  },
};
