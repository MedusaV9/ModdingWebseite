import type {TrailerStyleConfig} from '../config/types';

/** 15 — Glitchcore: Acid-Grün-Duotone, Slice-Glitches, Mono-Terminal-Typo. */
export const style: TrailerStyleConfig = {
  id: 15,
  slug: 'glitchcore',
  displayName: 'Glitchcore',
  durationSec: 17,
  track: 'glitch_idm',
  trackFallback: 'hype',
  palette: {bg: '#050505', ink: '#EAFFDD', accent: '#B7FF2E', accent2: '#FF2ECC'},
  fontPreset: 'mono',
  gradePreset: 'bw_accent',
  effects: ['glitch_bursts', 'chromatic', 'grain_heavy', 'shake_on_beat'],
  defaultTransition: 'zoom_in',
  structure: [
    {kind: 'type', text: 'SIGNAL *GEFUNDEN*', beats: 4, transition: 'cut', variant: 'slam'},
    {kind: 'splash', assetKey: 'clubNeon', text: 'ERR://DURST', beats: 4},
    {kind: 'splash', assetKey: 'macroCondensation', text: 'REBOOT.', beats: 4},
    {kind: 'render3d', assetKey: 'turntablePeach', text: 'SYSTEM: HYDRATION', beats: 6},
    {kind: 'type', text: 'PATCH *INSTALLIERT*', beats: 4, variant: 'slam'},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'SIGNAL GEFUNDEN.',
    mid: ['ISOTONISCH', 'VITAMINE + ELEKTROLYTE'],
    cta: 'UPDATE *DEINEN* DURST',
  },
  sfxPlan: {
    cues: [
      {name: 'ui_tick', beat: 0, volume: 0.75},
      {name: 'impact_1', beat: 8, volume: 0.85},
      {name: 'impact_2', beat: 16, volume: 0.85},
    ],
    onSceneCut: 'impact',
    cutVolume: 0.45,
  },
};
