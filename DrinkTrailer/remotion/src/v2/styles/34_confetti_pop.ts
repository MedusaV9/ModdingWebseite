import type {TrailerStyleConfig} from '../config/types';

/** 34 — Confetti Pop: Party-Countdown, Konfetti-Sticker, helle Feierlaune. */
export const style: TrailerStyleConfig = {
  id: 34,
  slug: 'confetti_pop',
  displayName: 'Confetti Pop',
  durationSec: 15,
  track: 'party_horns',
  trackFallback: 'hype',
  palette: {bg: '#FFF3E0', ink: '#4A2A3A', accent: '#FF4FA0', accent2: '#FFC53D'},
  fontPreset: 'hype',
  gradePreset: 'none',
  effects: ['stickers', 'film_burn', 'shake_on_beat', 'grain'],
  stickers: ['🎉', '🎊', '🥳', '✨', '🍑'],
  defaultTransition: 'zoom_in',
  structure: [
    {kind: 'countdown', text: '3', beats: 5, transition: 'cut'},
    {kind: 'splash', assetKey: 'poolSplash', text: 'PARTY!', beats: 5},
    {kind: 'lineup', variant: 'grid', beats: 6},
    {kind: 'type', text: '*CHEERS!*', beats: 4, variant: 'slam'},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'CHEERS!',
    mid: ['KALORIENARM', 'SPARKLING VITAMIN DRINK'],
    cta: 'Bring die *gute* Laune mit',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.75},
      {name: 'ui_tick', beat: 2, volume: 0.75},
      {name: 'impact_1', beat: 5, volume: 0.85},
      {name: 'sparkle_pop', beat: 10, volume: 0.7},
      {name: 'sparkle_pop', beat: 16, volume: 0.7},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.5,
  },
};
