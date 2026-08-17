import type {TrailerStyleConfig} from '../config/types';

/** 25 — Ingredient Story: nüchtern-frisches Labor-Grün, gestaffelte Zutatenliste. */
export const style: TrailerStyleConfig = {
  id: 25,
  slug: 'ingredient_story',
  displayName: 'Ingredient Story',
  durationSec: 21,
  track: 'science_pulse',
  trackFallback: 'clean',
  palette: {bg: '#F2F4F0', ink: '#22302A', accent: '#3AA66A', accent2: '#C9DCCB'},
  fontPreset: 'clean',
  gradePreset: 'none',
  effects: ['progress_dots', 'grain'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'type', text: 'WAS IST *WIRKLICH* DRIN?', beats: 5, transition: 'cut', variant: 'slam'},
    {kind: 'ingredients', text: 'VITAMIN C + B|MAGNESIUM|ELEKTROLYTE|WENIG KALORIEN', beats: 10},
    {kind: 'macro', assetKey: 'macroCondensation', text: 'Und ordentlich Kohlensäure', beats: 6},
    {kind: 'lineup', variant: 'grid', beats: 6},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'WAS IST WIRKLICH DRIN?',
    mid: ['Hydration with Benefits'],
    cta: 'Lies das Etikett. *Lächle.*',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.6},
      {name: 'ui_tick', beat: 5, volume: 0.6},
      {name: 'sparkle_pop', beat: 15, volume: 0.5},
    ],
    onSceneCut: null,
  },
};
