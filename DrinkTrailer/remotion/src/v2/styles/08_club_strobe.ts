import type {TrailerStyleConfig} from '../config/types';

/** 08 — Club Strobe: Neon-Grade, Burn-Flashes auf Cuts, Crash-Zooms, Technonacht. */
export const style: TrailerStyleConfig = {
  id: 8,
  slug: 'club_strobe',
  displayName: 'Club Strobe',
  durationSec: 17,
  track: 'club_techno',
  trackFallback: 'hype',
  palette: {bg: '#06060E', ink: '#FFFFFF', accent: '#00E5FF', accent2: '#FF2E97'},
  fontPreset: 'hype',
  gradePreset: 'neon',
  effects: ['glitch_bursts', 'chromatic', 'shake_on_beat', 'grain_heavy', 'film_burn'],
  defaultTransition: 'zoom_in',
  structure: [
    {kind: 'splash', assetKey: 'clubNeon', text: 'LAUT.', beats: 4, transition: 'cut'},
    {kind: 'type', text: 'DIE NACHT IST *JUNG*', beats: 4, variant: 'slam'},
    {kind: 'splash', assetKey: 'poolSplash', text: 'NASS.', beats: 4},
    {kind: 'render3d', assetKey: 'turntablePeach', text: 'SPARKLING VITAMIN DRINK', beats: 6},
    {kind: 'splash', assetKey: 'clubNeon', text: 'WEITER.', beats: 4},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'DIE NACHT IST JUNG.',
    mid: ['KALORIENARM', 'ISOTONISCH'],
    cta: 'TANZ *WEITER*',
  },
  sfxPlan: {
    cues: [
      {name: 'impact_1', beat: 0, volume: 0.9},
      {name: 'riser', beat: 8, volume: 0.6},
      {name: 'impact_2', beat: 12, volume: 0.9},
      {name: 'riser', beat: 18, volume: 0.6},
    ],
    onSceneCut: 'impact',
    cutVolume: 0.5,
  },
};
