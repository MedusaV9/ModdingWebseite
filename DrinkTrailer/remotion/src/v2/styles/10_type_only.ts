import type {TrailerStyleConfig} from '../config/types';

/** 10 — Type Only: null Bilder, reine Kinetik-Typo auf Creme — Slam, Lines, Tracking. */
export const style: TrailerStyleConfig = {
  id: 10,
  slug: 'type_only',
  displayName: 'Type Only',
  durationSec: 15,
  track: 'minimal_pulse',
  trackFallback: 'clean',
  palette: {bg: '#FAF3EC', ink: '#2A2A2A', accent: '#F2AC8F', accent2: '#CBD97A'},
  fontPreset: 'clean',
  gradePreset: 'none',
  effects: ['progress_bar'],
  defaultTransition: 'cut',
  structure: [
    {kind: 'type', text: 'DURST IST *LAUT*', beats: 5, variant: 'slam'},
    {kind: 'type', text: 'Sparkling Vitamin Drink|Isotonisch|Kalorienarm', beats: 6, variant: 'lines'},
    {kind: 'type', text: 'EARLY', beats: 5, variant: 'tracking'},
    {kind: 'type', text: 'TRINK *LEISE* WEITER', beats: 4, variant: 'slam'},
    {kind: 'endcard', beats: 6},
  ],
  copy: {
    hook: 'DURST IST LAUT.',
    mid: ['Vitamine + Elektrolyte', 'Hydration with Benefits'],
    cta: 'Mehr *Worte* braucht es nicht',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.6},
      {name: 'ui_tick', beat: 5, volume: 0.6},
      {name: 'ui_tick', beat: 11, volume: 0.6},
      {name: 'sparkle_pop', beat: 16, volume: 0.55},
    ],
    onSceneCut: null,
  },
};
