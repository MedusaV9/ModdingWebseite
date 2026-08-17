import type {TrailerStyleConfig} from '../config/types';

/** 31 — Emoji Storm: knalliges Gelb, Sticker-Gewitter, kurze laute Slams. */
export const style: TrailerStyleConfig = {
  id: 31,
  slug: 'emoji_storm',
  displayName: 'Emoji Storm',
  durationSec: 15,
  track: 'kawaii_rush',
  trackFallback: 'hype',
  palette: {bg: '#FFDE59', ink: '#3A2A00', accent: '#FF3D6E', accent2: '#35C9E8'},
  fontPreset: 'y2k',
  gradePreset: 'none',
  effects: ['stickers', 'shake_on_beat', 'grain'],
  stickers: ['🍑', '⚡', '💦', '✨', '🍋', '🔥', '💚', '🫧'],
  defaultTransition: 'zoom_in',
  structure: [
    {kind: 'type', text: 'OK. *WOW.*', beats: 5, transition: 'cut', variant: 'slam'},
    {kind: 'splash', assetKey: 'poolSplash', text: 'SPLASH!!', beats: 5},
    {kind: 'type', text: 'DAS IST *EARLY*', beats: 5, variant: 'slam'},
    {kind: 'splash', assetKey: 'splashPeach', text: 'JUICY!!', beats: 5},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'OK. WOW.',
    mid: ['SPARKLING VITAMIN DRINK', 'KALORIENARM'],
    cta: 'MEHR *DAVON*',
  },
  sfxPlan: {
    cues: [
      {name: 'sparkle_pop', beat: 0, volume: 0.7},
      {name: 'sparkle_pop', beat: 5, volume: 0.7},
      {name: 'impact_1', beat: 10, volume: 0.8},
      {name: 'sparkle_pop', beat: 15, volume: 0.7},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.5,
  },
};
