import type {TrailerStyleConfig} from '../config/types';

/** 04 — VHS Retro: Tape-Wobble, Scanlines, Timecode-HUD, 90s-Heimvideo-Charme. */
export const style: TrailerStyleConfig = {
  id: 4,
  slug: 'vhs_retro',
  displayName: 'VHS Retro',
  durationSec: 20,
  track: 'retro_tape',
  trackFallback: 'clean',
  palette: {bg: '#1A1410', ink: '#F2E8D8', accent: '#FFB000', accent2: '#FF6B9C'},
  fontPreset: 'mono',
  gradePreset: 'vhs',
  effects: ['grain_heavy'],
  defaultTransition: 'cut',
  structure: [
    {kind: 'hero', assetKey: 'picnic', text: 'SOMMER 2026*', beats: 7, transition: 'cut'},
    {kind: 'lifestyle', assetKey: 'lifestyleFriends16x9', text: 'MIT DEN BESTEN', beats: 6},
    {kind: 'macro', assetKey: 'pourGlass', text: 'REC ● EISKALT', beats: 6},
    {kind: 'splash', assetKey: 'sunriseRun', text: 'PLAY ▶', beats: 5},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'SOMMER, WIE FRÜHER.',
    mid: ['SPARKLING VITAMIN DRINK', 'ISOTONISCH'],
    cta: 'ZURÜCKSPULEN? *NACHSCHENKEN.*',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.6},
      {name: 'fizz_open', beat: 7, volume: 0.6},
      {name: 'ui_tick', beat: 24, volume: 0.6},
    ],
    onSceneCut: null,
  },
};
