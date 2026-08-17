import type {TrailerStyleConfig} from '../config/types';

/** 26 — Before/After: diagonale Wipes von grau-müde zu frisch-farbig. */
export const style: TrailerStyleConfig = {
  id: 26,
  slug: 'before_after',
  displayName: 'Before / After',
  durationSec: 17,
  track: 'swell_shift',
  trackFallback: 'hype',
  palette: {bg: '#20242A', ink: '#F5F2EC', accent: '#CBD97A', accent2: '#E77F4F'},
  fontPreset: 'hype',
  gradePreset: 'none',
  effects: ['grain', 'progress_bar'],
  defaultTransition: 'mask_diagonal',
  structure: [
    {kind: 'type', text: 'KENNST DU *DAS*?', beats: 4, transition: 'cut', variant: 'slam'},
    {kind: 'beforeafter', assetKeys: ['studyDesk', 'poolSplash'], text: 'MÜDE|WACH', beats: 10},
    {kind: 'beforeafter', assetKeys: ['lifestyleGym', 'picnic'], text: 'LEER|GELADEN', beats: 10},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'KENNST DU DAS?',
    mid: ['ISOTONISCH', 'ELEKTROLYTE'],
    cta: 'Von *müde* zu Early',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.65},
      {name: 'whoosh', beat: 8, volume: 0.6},
      {name: 'impact_1', beat: 11, volume: 0.75},
      {name: 'whoosh', beat: 18, volume: 0.6},
      {name: 'impact_2', beat: 21, volume: 0.75},
    ],
    onSceneCut: null,
  },
};
