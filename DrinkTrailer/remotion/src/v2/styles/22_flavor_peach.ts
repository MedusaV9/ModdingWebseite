import type {TrailerStyleConfig} from '../config/types';

/** 22 — Flavor Peach: Sortenporträt Pfirsich, Dosen-Masken, Rosé-Wärme. */
export const style: TrailerStyleConfig = {
  id: 22,
  slug: 'flavor_peach',
  displayName: 'Flavor Peach',
  durationSec: 17,
  track: 'peach_pop',
  trackFallback: 'clean',
  palette: {bg: '#F7E3DD', ink: '#5A3A38', accent: '#E7897B', accent2: '#F2AC8F'},
  fontPreset: 'clean',
  gradePreset: 'warm',
  effects: ['light_leak', 'grain', 'stickers'],
  stickers: ['🍑', '✨', '🫧'],
  defaultTransition: 'mask_can',
  structure: [
    {kind: 'hero', assetKey: 'heroPeach', text: 'WEISSER *PFIRSICH*', beats: 7, transition: 'cut'},
    {kind: 'splash', assetKey: 'splashPeach', text: 'SAFTIG.', beats: 5},
    {kind: 'macro', assetKey: 'macroCondensation', text: 'Samtig süß, null schwer', beats: 5},
    {kind: 'render3d', assetKey: 'turntablePeach', text: 'SPARKLING VITAMIN DRINK', beats: 5},
    {kind: 'endcard', assetKey: 'peach', beats: 8},
  ],
  copy: {
    hook: 'WEISSER PFIRSICH.',
    mid: ['Kalorienarm', 'Vitamine + Elektrolyte'],
    cta: 'Die *Sommersorte*',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 1, volume: 0.6},
      {name: 'sparkle_pop', beat: 8, volume: 0.55},
      {name: 'sparkle_pop', beat: 17, volume: 0.5},
    ],
    onSceneCut: null,
  },
};
