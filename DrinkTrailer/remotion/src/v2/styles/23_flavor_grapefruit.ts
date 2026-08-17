import type {TrailerStyleConfig} from '../config/types';

/** 23 — Flavor Grapefruit: Sortenporträt Grapefruit, House-Groove, spritzige Koralle. */
export const style: TrailerStyleConfig = {
  id: 23,
  slug: 'flavor_grapefruit',
  displayName: 'Flavor Grapefruit',
  durationSec: 17,
  track: 'house_groove',
  trackFallback: 'hype',
  palette: {bg: '#F9E8DC', ink: '#6B3226', accent: '#F2673C', accent2: '#F2AC8F'},
  fontPreset: 'clean',
  gradePreset: 'none',
  effects: ['grain', 'light_leak', 'progress_dots'],
  defaultTransition: 'mask_can',
  structure: [
    {kind: 'hero', assetKey: 'heroGrapefruit', text: 'PINK *GRAPEFRUIT*', beats: 7, transition: 'cut'},
    {kind: 'splash', assetKey: 'splashGrapefruit16x9', text: 'ZESTY.', beats: 5},
    {kind: 'macro', assetKey: 'pourGlass', text: 'Herb trifft spritzig', beats: 5},
    {kind: 'lineup', beats: 5},
    {kind: 'endcard', assetKey: 'grapefruit', beats: 8},
  ],
  copy: {
    hook: 'PINK GRAPEFRUIT.',
    mid: ['Isotonisch', 'Kalorienarm'],
    cta: 'Die Sorte mit *Biss*',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 1, volume: 0.6},
      {name: 'sparkle_pop', beat: 12, volume: 0.5},
      {name: 'impact_1', beat: 22, volume: 0.6},
    ],
    onSceneCut: null,
  },
};
