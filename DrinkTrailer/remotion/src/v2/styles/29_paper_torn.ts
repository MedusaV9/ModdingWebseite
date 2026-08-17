import type {TrailerStyleConfig} from '../config/types';

/** 29 — Paper Torn: gerissene Papierkanten als Übergänge, Craft-Palette, Zine-Look. */
export const style: TrailerStyleConfig = {
  id: 29,
  slug: 'paper_torn',
  displayName: 'Paper Torn',
  durationSec: 18,
  track: 'acoustic_strum',
  trackFallback: 'clean',
  palette: {bg: '#EFE6D8', ink: '#3E3428', accent: '#C4552D', accent2: '#7A8C5A'},
  fontPreset: 'clean',
  gradePreset: 'none',
  effects: ['grain_heavy', 'progress_dots'],
  defaultTransition: 'mask_torn',
  structure: [
    {kind: 'hero', assetKey: 'botanical', text: 'FRISCH *AUFGERISSEN*', beats: 6, transition: 'cut'},
    {kind: 'collage', assetKeys: ['heroGrapefruit', 'picnic', 'sunriseRun'], text: 'SEITE FÜR *SEITE*', beats: 8},
    {kind: 'quote', text: 'Wie ein guter Zine: kurz, ehrlich, erfrischend. — EARLY', beats: 5},
    {kind: 'splash', assetKey: 'picnic', text: 'RATSCH.', beats: 5},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'FRISCH AUFGERISSEN.',
    mid: ['Vitamine + Elektrolyte', 'Kalorienarm'],
    cta: 'Reiß dich *los*',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 1, volume: 0.55},
      {name: 'sparkle_pop', beat: 14, volume: 0.5},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.35,
  },
};
