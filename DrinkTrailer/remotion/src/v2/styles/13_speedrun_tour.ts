import type {TrailerStyleConfig} from '../config/types';

/** 13 — Speedrun Tour: 2-Beat-Cuts durch alle Locations, Mono-Font, DnB-Tempo. */
export const style: TrailerStyleConfig = {
  id: 13,
  slug: 'speedrun_tour',
  displayName: 'Speedrun Tour',
  durationSec: 15,
  track: 'dnb_rush',
  trackFallback: 'hype',
  palette: {bg: '#0E1414', ink: '#E8FFF5', accent: '#3DFFB0', accent2: '#FFD23D'},
  fontPreset: 'mono',
  gradePreset: 'cool',
  effects: ['progress_bar', 'shake_on_beat', 'chromatic', 'grain'],
  defaultTransition: 'whip_left',
  structure: [
    {kind: 'hero', assetKey: 'heroPeach', text: 'ANY% DURST RUN', beats: 2, transition: 'cut'},
    {kind: 'splash', assetKey: 'splashPeach', text: 'CP 1', beats: 2},
    {kind: 'macro', assetKey: 'macroCondensation', text: 'CP 2', beats: 2, transition: 'whip_right'},
    {kind: 'lifestyle', assetKey: 'sunriseRun', text: 'CP 3', beats: 2},
    {kind: 'splash', assetKey: 'poolSplash', text: 'CP 4', beats: 2, transition: 'whip_right'},
    {kind: 'hero', assetKey: 'clubNeon', text: 'CP 5', beats: 2},
    {kind: 'splash', assetKey: 'gymChalk', text: 'CP 6', beats: 2, transition: 'whip_right'},
    {kind: 'lifestyle', assetKey: 'picnic', text: 'CP 7', beats: 2},
    {kind: 'render3d', assetKey: 'turntablePeach', text: 'FINAL BOSS: DURST', beats: 4, transition: 'zoom_in'},
    {kind: 'type', text: 'NEUE *BESTZEIT*', beats: 4, variant: 'slam'},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'ANY% DURST RUN',
    mid: ['ISOTONISCH', 'ELEKTROLYTE'],
    cta: 'WR: *EIN* SCHLUCK',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.7},
      {name: 'riser', beat: 12, volume: 0.6},
      {name: 'impact_1', beat: 16, volume: 0.9},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.55,
  },
};
