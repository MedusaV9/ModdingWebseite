import type {TrailerStyleConfig} from '../config/types';

/** 11 — Split Duo: geteilte Frames, zwei Welten pro Schnitt, Bar-Masken. */
export const style: TrailerStyleConfig = {
  id: 11,
  slug: 'split_duo',
  displayName: 'Split Duo',
  durationSec: 18,
  track: 'duo_beat',
  trackFallback: 'hype',
  palette: {bg: '#1E2228', ink: '#F5F2ED', accent: '#F2AC8F', accent2: '#7FB5B5'},
  fontPreset: 'clean',
  gradePreset: 'cool',
  effects: ['grain', 'progress_dots'],
  defaultTransition: 'mask_bars',
  structure: [
    {kind: 'split', assetKeys: ['lifestyleGym', 'poolSplash'], text: 'TRAINING|ABKÜHLUNG', variant: '2v', beats: 8, transition: 'cut'},
    {kind: 'type', text: 'EIN DRINK. *BEIDE* WELTEN.', beats: 5, variant: 'slam'},
    {kind: 'split', assetKeys: ['studyDesk', 'picnic'], text: 'FOKUS|FREIZEIT', variant: '2v', beats: 8},
    {kind: 'splash', assetKey: 'pourGlass', text: 'PROST.', beats: 5},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'EIN DRINK. BEIDE WELTEN.',
    mid: ['ISOTONISCH', 'KALORIENARM'],
    cta: 'Für *jede* Hälfte deines Tages',
  },
  sfxPlan: {
    cues: [
      {name: 'impact_1', beat: 0, volume: 0.7},
      {name: 'sparkle_pop', beat: 13, volume: 0.5},
      {name: 'impact_2', beat: 21, volume: 0.7},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.45,
  },
};
