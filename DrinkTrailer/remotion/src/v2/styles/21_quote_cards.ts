import type {TrailerStyleConfig} from '../config/types';

/** 21 — Quote Cards: drei Serifen-Zitatkarten auf Papiercreme, ruhige Fades. */
export const style: TrailerStyleConfig = {
  id: 21,
  slug: 'quote_cards',
  displayName: 'Quote Cards',
  durationSec: 18,
  track: 'quote_piano',
  trackFallback: 'clean',
  musicVolume: 0.85,
  palette: {bg: '#F7F3EB', ink: '#33302B', accent: '#C77E5A', accent2: '#9AA88E'},
  fontPreset: 'serif',
  gradePreset: 'none',
  effects: ['grain', 'progress_dots'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'quote', text: 'Endlich ein Drink, der beides kann. — Mia, 24', beats: 7, transition: 'cut'},
    {kind: 'quote', text: 'Schmeckt nach Sommer. Ohne Reue. — Jonas, 27', beats: 7},
    {kind: 'quote', text: 'Mein Feierabend hat jetzt Kohlensäure. — Aylin, 22', beats: 7},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Was Early-Trinker sagen.',
    mid: ['Sparkling Vitamin Drink'],
    cta: 'Überzeug dich *selbst*',
  },
  sfxPlan: {
    cues: [
      {name: 'sparkle_pop', beat: 0, volume: 0.4},
      {name: 'sparkle_pop', beat: 7, volume: 0.4},
      {name: 'sparkle_pop', beat: 14, volume: 0.4},
    ],
    onSceneCut: null,
  },
};
