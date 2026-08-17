import type {TrailerStyleConfig} from '../config/types';

/** 14 — Cinematic Epic: Letterbox, Gold auf Anthrazit, langsame Kamera, Trailer-Pathos. */
export const style: TrailerStyleConfig = {
  id: 14,
  slug: 'cinematic_epic',
  displayName: 'Cinematic Epic',
  durationSec: 26,
  track: 'epic_orchestral',
  trackFallback: 'clean',
  palette: {bg: '#0B0E12', ink: '#EDE6D6', accent: '#C9A227', accent2: '#3A4A5A'},
  fontPreset: 'hype',
  gradePreset: 'cool',
  effects: ['letterbox', 'grain', 'vignette', 'film_burn'],
  defaultTransition: 'luma',
  structure: [
    {kind: 'hero', assetKey: 'epicSmoke', text: 'AUS DEM NEBEL', beats: 9, transition: 'cut'},
    {kind: 'type', text: 'EARLY', beats: 5, variant: 'tracking'},
    {kind: 'render3d', assetKey: 'dollyPeach16x9', text: 'SPARKLING VITAMIN DRINK', beats: 9},
    {kind: 'macro', assetKey: 'macroCondensation', text: 'GESCHMIEDET AUS KOHLENSÄURE', beats: 6},
    {kind: 'lineup', beats: 6},
    {kind: 'endcard', beats: 10},
  ],
  copy: {
    hook: 'AUS DEM NEBEL.',
    mid: ['HYDRATION WITH BENEFITS', 'VITAMINE + ELEKTROLYTE'],
    cta: 'EINE *LEGENDE* IN DREI SORTEN',
  },
  sfxPlan: {
    cues: [
      {name: 'riser', beat: 4, volume: 0.6},
      {name: 'impact_1', beat: 9, volume: 1},
      {name: 'riser', beat: 24, volume: 0.6},
      {name: 'impact_2', beat: 29, volume: 1},
    ],
    onSceneCut: null,
  },
};
