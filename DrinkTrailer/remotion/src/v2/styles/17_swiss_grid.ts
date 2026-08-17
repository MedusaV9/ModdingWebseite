import type {TrailerStyleConfig} from '../config/types';

/** 17 — Swiss Grid: Internationale Typografie, Rot-Akzent, 2x2-Raster, harte Cuts. */
export const style: TrailerStyleConfig = {
  id: 17,
  slug: 'swiss_grid',
  displayName: 'Swiss Grid',
  durationSec: 18,
  track: 'minimal_click',
  trackFallback: 'clean',
  palette: {bg: '#F4F1EC', ink: '#111111', accent: '#E63946', accent2: '#B0B0B0'},
  fontPreset: 'clean',
  gradePreset: 'none',
  effects: ['progress_bar'],
  defaultTransition: 'cut',
  structure: [
    {kind: 'type', text: 'Form.|Funktion.|Geschmack.', beats: 6, variant: 'lines'},
    {kind: 'split', assetKeys: ['minimalFloat', 'macroCondensation', 'pourGlass', 'lineup'], variant: '2x2', beats: 8},
    {kind: 'ingredients', text: 'ISOTONISCH|KALORIENARM|VITAMINE + ELEKTROLYTE', beats: 8},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Form. Funktion. Geschmack.',
    mid: ['Sparkling Vitamin Drink'],
    cta: 'Gut gestaltet. *Besser* getrunken.',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.6},
      {name: 'ui_tick', beat: 6, volume: 0.6},
      {name: 'ui_tick', beat: 14, volume: 0.6},
    ],
    onSceneCut: null,
  },
};
