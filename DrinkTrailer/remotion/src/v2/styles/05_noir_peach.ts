import type {TrailerStyleConfig} from '../config/types';

/** 05 — Noir Peach: Schwarzweiß-Kontrast mit Rosé-Duotone, Serifen, Kino-Bars. */
export const style: TrailerStyleConfig = {
  id: 5,
  slug: 'noir_peach',
  displayName: 'Noir Peach',
  durationSec: 20,
  track: 'noir_jazz',
  trackFallback: 'clean',
  musicVolume: 0.9,
  palette: {bg: '#0A0A0A', ink: '#F5EFE6', accent: '#E7B7B7', accent2: '#6B4A4A'},
  fontPreset: 'serif',
  gradePreset: 'noir',
  effects: ['letterbox', 'grain', 'vignette'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'macro', assetKey: 'macroCondensation', text: 'Kalt. Still. Perlend.', beats: 7, transition: 'cut'},
    {kind: 'quote', text: 'Manche Drinks schreien. Dieser flüstert. — EARLY', beats: 8},
    {kind: 'hero', assetKey: 'heroPeach', text: 'Pfirsich, bei Nacht', beats: 7},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Pfirsich, bei Nacht.',
    mid: ['Hydration with Benefits', 'Kalorienarm'],
    cta: 'Für die *leisen* Stunden',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 1, volume: 0.45},
      {name: 'sparkle_pop', beat: 15, volume: 0.4},
    ],
    onSceneCut: null,
  },
};
