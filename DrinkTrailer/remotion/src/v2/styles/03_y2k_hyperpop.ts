import type {TrailerStyleConfig} from '../config/types';

/** 03 — Y2K Hyperpop: Chrome-Pink/Cyan, Glitter-Sticker, 150-BPM-Zuckerrausch. */
export const style: TrailerStyleConfig = {
  id: 3,
  slug: 'y2k_hyperpop',
  displayName: 'Y2K Hyperpop',
  durationSec: 20,
  track: 'hyperpop_y2k',
  trackFallback: 'hype',
  palette: {bg: '#14001F', ink: '#FFFFFF', accent: '#FF4FD8', accent2: '#4FE8FF'},
  fontPreset: 'y2k',
  gradePreset: 'neon',
  effects: ['chromatic', 'glitch_bursts', 'stickers', 'grain'],
  stickers: ['💿', '✨', '💖', '⭐', '🫧'],
  defaultTransition: 'zoom_in',
  structure: [
    {kind: 'type', text: 'SO *SÜSS* OHNE ZUCKER', beats: 6, transition: 'cut', variant: 'slam'},
    {kind: 'splash', assetKey: 'poolSplash', text: 'SPLASH!', beats: 6},
    {kind: 'split', assetKeys: ['clubNeon', 'poolSplash'], text: 'NIGHT|DAY', variant: '2v', beats: 8, transition: 'mask_bars'},
    {kind: 'splash', assetKey: 'splashLemonMint', text: 'FRESH!', beats: 6},
    {kind: 'type', text: 'EARLY', beats: 6, variant: 'tracking'},
    {kind: 'endcard', beats: 10},
  ],
  copy: {
    hook: 'SO SÜSS OHNE ZUCKER',
    mid: ['SPARKLING VITAMIN DRINK', 'KALORIENARM'],
    cta: 'DEIN NEUER *CRUSH*',
  },
  sfxPlan: {
    cues: [
      {name: 'sparkle_pop', beat: 0, volume: 0.7},
      {name: 'sparkle_pop', beat: 12, volume: 0.7},
      {name: 'riser', beat: 20, volume: 0.55},
      {name: 'impact_1', beat: 26, volume: 0.8},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.45,
  },
};
