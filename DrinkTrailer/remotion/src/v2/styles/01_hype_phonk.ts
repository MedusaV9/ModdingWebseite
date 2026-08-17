import type {TrailerStyleConfig} from '../config/types';

/** 01 — Hype Phonk: nächtlicher Street-Look, harte Beat-Cuts, RGB-Splits, Drift-808s. */
export const style: TrailerStyleConfig = {
  id: 1,
  slug: 'hype_phonk',
  displayName: 'Hype Phonk',
  durationSec: 21,
  track: 'phonk_drift',
  trackFallback: 'hype',
  palette: {bg: '#101014', ink: '#F5F0E8', accent: '#FF4D4D', accent2: '#8A8AFF'},
  fontPreset: 'hype',
  gradePreset: 'cool',
  effects: ['grain_heavy', 'shake_on_beat', 'chromatic', 'glitch_bursts', 'vignette'],
  defaultTransition: 'whip_left',
  structure: [
    {kind: 'type', text: 'KEIN ZUCKER. *KEIN* LIMIT.', beats: 4, transition: 'cut', variant: 'slam'},
    {kind: 'splash', assetKey: 'splashPeach', text: 'BOOM.', beats: 4, transition: 'zoom_in'},
    {kind: 'hero', assetKey: 'clubNeon', text: 'DIE NACHT GEHÖRT *DIR*', beats: 6},
    {kind: 'render3d', assetKey: 'turntablePeach', text: 'SPARKLING VITAMIN DRINK', beats: 8},
    {kind: 'splash', assetKey: 'gymChalk', text: 'VOLLGAS.', beats: 4},
    {kind: 'macro', assetKey: 'macroCondensation', text: 'EISKALT SERVIERT', beats: 4},
    {kind: 'type', text: 'VITAMINE + *ELEKTROLYTE*', beats: 4, variant: 'slam'},
    {kind: 'endcard', beats: 8, transition: 'zoom_in'},
  ],
  copy: {
    hook: 'KEIN ZUCKER. KEIN LIMIT.',
    mid: ['ISOTONISCH', 'VITAMINE + ELEKTROLYTE'],
    cta: 'JETZT *EARLY* HOLEN',
  },
  sfxPlan: {
    cues: [
      {name: 'fizz_open', beat: 0, volume: 0.7},
      {name: 'impact_1', beat: 8, volume: 0.9},
      {name: 'riser', beat: 26, volume: 0.6},
      {name: 'impact_2', beat: 30, volume: 0.9},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.5,
  },
};
