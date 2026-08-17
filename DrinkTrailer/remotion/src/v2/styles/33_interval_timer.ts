import type {TrailerStyleConfig} from '../config/types';

/** 33 — Interval Timer: HIIT-Timer-HUD, Mono-Zahlen, Work/Rest-Rhythmus. */
export const style: TrailerStyleConfig = {
  id: 33,
  slug: 'interval_timer',
  displayName: 'Interval Timer',
  durationSec: 19,
  track: 'interval_beeps',
  trackFallback: 'hype',
  palette: {bg: '#101418', ink: '#E8F5F2', accent: '#3DFF88', accent2: '#FF5B3D'},
  fontPreset: 'mono',
  gradePreset: 'cool',
  effects: ['hiit_timer', 'progress_bar', 'shake_on_beat', 'grain'],
  defaultTransition: 'whip_up',
  structure: [
    {kind: 'countdown', text: '3', assetKey: 'gymChalk', beats: 6, transition: 'cut'},
    {kind: 'lifestyle', assetKey: 'lifestyleGym', text: 'WORK: GIB ALLES', beats: 6},
    {kind: 'splash', assetKey: 'gymChalk', text: 'REST: TRINK.', beats: 5},
    {kind: 'ingredients', text: 'ISOTONISCH|ELEKTROLYTE|KALORIENARM', beats: 8},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'WORK. REST. EARLY.',
    mid: ['ISOTONISCH', 'ELEKTROLYTE'],
    cta: 'Deine *Pause* schmeckt jetzt',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.8},
      {name: 'ui_tick', beat: 2, volume: 0.8},
      {name: 'ui_tick', beat: 4, volume: 0.8},
      {name: 'impact_1', beat: 6, volume: 0.85},
      {name: 'ui_tick', beat: 17, volume: 0.7},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.45,
  },
};
