import type {TrailerStyleConfig} from '../config/types';

/** 28 — Neon Outline: Leuchtreklame-Typo mit Flicker, Bloom-Glow, Nacht-Cyan/Pink. */
export const style: TrailerStyleConfig = {
  id: 28,
  slug: 'neon_outline',
  displayName: 'Neon Outline',
  durationSec: 17,
  track: 'electro_night',
  trackFallback: 'hype',
  palette: {bg: '#07070F', ink: '#EDEDFF', accent: '#00FFC8', accent2: '#FF3DF0'},
  fontPreset: 'hype',
  gradePreset: 'neon',
  effects: ['bloom', 'grain', 'chromatic'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'type', text: 'SPARKLING|VITAMIN|DRINK', beats: 10, transition: 'cut', variant: 'neon'},
    {kind: 'splash', assetKey: 'clubNeon', text: 'OPEN LATE.', beats: 6},
    {kind: 'type', text: 'EARLY', beats: 8, variant: 'neon'},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'SPARKLING VITAMIN DRINK',
    mid: ['ISOTONISCH', 'KALORIENARM'],
    cta: 'LEUCHTET *VON INNEN*',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.55},
      {name: 'fizz_open', beat: 10, volume: 0.6},
      {name: 'sparkle_pop', beat: 18, volume: 0.55},
    ],
    onSceneCut: null,
  },
};
