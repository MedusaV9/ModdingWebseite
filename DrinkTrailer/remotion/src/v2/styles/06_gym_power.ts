import type {TrailerStyleConfig} from '../config/types';

/** 06 — Gym Power: Countdown-Start, Chalk-Dust, Whip-Ups, Elektrolyt-Claims. */
export const style: TrailerStyleConfig = {
  id: 6,
  slug: 'gym_power',
  displayName: 'Gym Power',
  durationSec: 18,
  track: 'gym_trap',
  trackFallback: 'hype',
  palette: {bg: '#15181C', ink: '#F2F5F7', accent: '#CBD97A', accent2: '#4A5A66'},
  fontPreset: 'hype',
  gradePreset: 'cool',
  effects: ['shake_on_beat', 'grain', 'progress_bar', 'chromatic'],
  defaultTransition: 'whip_up',
  structure: [
    {kind: 'countdown', text: '3', assetKey: 'gymChalk', beats: 6, transition: 'cut'},
    {kind: 'splash', assetKey: 'gymChalk', text: 'LETZTER SATZ.', beats: 5},
    {kind: 'lifestyle', assetKey: 'lifestyleGym', text: 'MEHR *REPS* MEHR FOKUS', beats: 6},
    {kind: 'type', text: 'REFUEL. *REPEAT.*', beats: 5, variant: 'slam'},
    {kind: 'ingredients', text: 'ISOTONISCH|ELEKTROLYTE|KALORIENARM', beats: 8},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'MEHR REPS. MEHR FOKUS.',
    mid: ['ISOTONISCH', 'VITAMINE + ELEKTROLYTE'],
    cta: 'DEIN *POST-WORKOUT* UPGRADE',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.7},
      {name: 'ui_tick', beat: 2, volume: 0.7},
      {name: 'impact_1', beat: 6, volume: 0.9},
      {name: 'riser', beat: 24, volume: 0.55},
      {name: 'impact_2', beat: 30, volume: 0.85},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.5,
  },
};
