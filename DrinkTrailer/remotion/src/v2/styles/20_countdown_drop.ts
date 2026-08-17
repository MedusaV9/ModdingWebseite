import type {TrailerStyleConfig} from '../config/types';

/** 20 — Countdown Drop: 3-2-1-Slams, Riser, Burn-Flash, dann der Drop. */
export const style: TrailerStyleConfig = {
  id: 20,
  slug: 'countdown_drop',
  displayName: 'Countdown Drop',
  durationSec: 15,
  track: 'countdown_riser',
  trackFallback: 'hype',
  palette: {bg: '#14100A', ink: '#FFF4E0', accent: '#FF7A00', accent2: '#FFD23D'},
  fontPreset: 'hype',
  gradePreset: 'cool',
  effects: ['shake_on_beat', 'film_burn', 'chromatic', 'grain', 'progress_bar'],
  defaultTransition: 'zoom_in',
  structure: [
    {kind: 'countdown', text: '3', assetKey: 'clubNeon', beats: 6, transition: 'cut'},
    {kind: 'splash', assetKey: 'poolSplash', text: 'DROP.', beats: 4},
    {kind: 'render3d', assetKey: 'turntablePeach', text: 'SPARKLING VITAMIN DRINK', beats: 6},
    {kind: 'type', text: 'DER *DROP* DES SOMMERS', beats: 4, variant: 'slam'},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'DER DROP DES SOMMERS.',
    mid: ['KALORIENARM', 'ELEKTROLYTE'],
    cta: 'VERPASS IHN *NICHT*',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.8},
      {name: 'ui_tick', beat: 2, volume: 0.8},
      {name: 'ui_tick', beat: 4, volume: 0.8},
      {name: 'riser', beat: 2, volume: 0.7},
      {name: 'impact_1', beat: 6, volume: 1},
      {name: 'impact_2', beat: 16, volume: 0.9},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.5,
  },
};
