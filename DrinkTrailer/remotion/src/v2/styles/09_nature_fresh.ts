import type {TrailerStyleConfig} from '../config/types';

/** 09 — Nature Fresh: botanisches Grün, Kreis-Masken, organische Ruhe. */
export const style: TrailerStyleConfig = {
  id: 9,
  slug: 'nature_fresh',
  displayName: 'Nature Fresh',
  durationSec: 19,
  track: 'forest_organic',
  trackFallback: 'clean',
  musicVolume: 0.9,
  palette: {bg: '#EAF2E3', ink: '#24391F', accent: '#5B8C4A', accent2: '#CBD97A'},
  fontPreset: 'clean',
  gradePreset: 'none',
  effects: ['grain', 'light_leak', 'progress_dots'],
  defaultTransition: 'mask_circle',
  structure: [
    {kind: 'hero', assetKey: 'botanical', text: 'Von der Natur *gelernt*', beats: 6, transition: 'cut'},
    {kind: 'macro', assetKey: 'bubblesUnderwater', text: 'Nur das Gute, fein perlend', beats: 5},
    {kind: 'lifestyle', assetKey: 'picnic', text: 'Draußen schmeckt es besser', beats: 5},
    {kind: 'lineup', beats: 6},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Von der Natur gelernt.',
    mid: ['Vitamine + Elektrolyte', 'Kalorienarm'],
    cta: 'Frisch wie *draußen*',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 2, volume: 0.5},
      {name: 'sparkle_pop', beat: 12, volume: 0.45},
    ],
    onSceneCut: null,
  },
};
