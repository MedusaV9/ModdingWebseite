import type {TrailerStyleConfig} from '../config/types';

/** 27 — Stop Motion: 12fps-Holds mit Pose-Jitter, Papier-Collage, Bastel-Charme. */
export const style: TrailerStyleConfig = {
  id: 27,
  slug: 'stop_motion',
  displayName: 'Stop Motion',
  durationSec: 18,
  track: 'quirk_claps',
  trackFallback: 'clean',
  palette: {bg: '#F3E9D7', ink: '#4A3A28', accent: '#E0703C', accent2: '#8FB573'},
  fontPreset: 'clean',
  gradePreset: 'warm',
  effects: ['stop_motion', 'grain_heavy'],
  defaultTransition: 'mask_torn',
  structure: [
    {kind: 'hero', assetKey: 'heroPeach', text: 'BILD FÜR *BILD* BESSER', beats: 6, transition: 'cut'},
    {kind: 'collage', assetKeys: ['splashPeach', 'botanical', 'picnic'], text: 'HANDGEMACHT? *FAST.*', beats: 8},
    {kind: 'splash', assetKey: 'pourGlass', text: 'KLICK.', beats: 5},
    {kind: 'type', text: 'EARLY IN *STOP* MOTION', beats: 4, variant: 'slam'},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'BILD FÜR BILD BESSER.',
    mid: ['Kalorienarm', 'Sparkling Vitamin Drink'],
    cta: 'Jede *Pose* ein Genuss',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.6},
      {name: 'ui_tick', beat: 6, volume: 0.6},
      {name: 'sparkle_pop', beat: 14, volume: 0.55},
      {name: 'ui_tick', beat: 19, volume: 0.6},
    ],
    onSceneCut: null,
  },
};
