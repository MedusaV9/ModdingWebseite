import type {TrailerStyleConfig} from '../config/types';

/** 24 — Flavor Lemon-Mint: Sortenporträt Zitrone-Minze, kühles Grün, Frische-Fokus. */
export const style: TrailerStyleConfig = {
  id: 24,
  slug: 'flavor_lemonmint',
  displayName: 'Flavor Lemon-Mint',
  durationSec: 17,
  track: 'mint_house',
  trackFallback: 'clean',
  palette: {bg: '#EDF5E0', ink: '#2F4A2A', accent: '#A8C93A', accent2: '#5BB58A'},
  fontPreset: 'clean',
  gradePreset: 'cool',
  effects: ['grain', 'light_leak', 'progress_dots'],
  defaultTransition: 'mask_can',
  structure: [
    {kind: 'hero', assetKey: 'heroLemonMint', text: 'ZITRONE *MINZE*', beats: 7, transition: 'cut'},
    {kind: 'splash', assetKey: 'splashLemonMint', text: 'FROSTIG.', beats: 5},
    {kind: 'macro', assetKey: 'bubblesUnderwater', text: 'Kälter geht Frische nicht', beats: 5},
    {kind: 'render3d', assetKey: 'turntablePeach', text: 'SPARKLING VITAMIN DRINK', beats: 5},
    {kind: 'endcard', assetKey: 'lemonmint', beats: 8},
  ],
  copy: {
    hook: 'ZITRONE-MINZE.',
    mid: ['Vitamine + Elektrolyte', 'Isotonisch'],
    cta: 'Die *Frische-Sorte*',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 1, volume: 0.6},
      {name: 'sparkle_pop', beat: 8, volume: 0.5},
      {name: 'sparkle_pop', beat: 17, volume: 0.5},
    ],
    onSceneCut: null,
  },
};
