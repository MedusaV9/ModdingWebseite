import type {TrailerStyleConfig} from '../config/types';

/** 35 — Grand Finale: 30s Best-of — alle Sorten, 3D-Render, Zoom-Tunnel, Countdown. */
export const style: TrailerStyleConfig = {
  id: 35,
  slug: 'grand_finale',
  displayName: 'Grand Finale',
  durationSec: 30,
  track: 'finale_mashup',
  trackFallback: 'hype',
  palette: {bg: '#12100E', ink: '#FAF3EC', accent: '#F2AC8F', accent2: '#CBD97A'},
  fontPreset: 'hype',
  gradePreset: 'cool',
  effects: ['film_burn', 'shake_on_beat', 'chromatic', 'grain', 'progress_bar'],
  defaultTransition: 'whip_left',
  structure: [
    {kind: 'type', text: 'DAS *GROSSE* FINALE', beats: 5, transition: 'cut', variant: 'slam'},
    {kind: 'hero', assetKey: 'epicSmoke', text: 'EIN SOMMER. EIN DRINK.', beats: 6, transition: 'luma'},
    {kind: 'splash', assetKey: 'splashPeach', text: 'PFIRSICH.', beats: 4},
    {kind: 'splash', assetKey: 'splashGrapefruit16x9', text: 'GRAPEFRUIT.', beats: 4, transition: 'whip_right'},
    {kind: 'splash', assetKey: 'splashLemonMint', text: 'ZITRONE-MINZE.', beats: 4},
    {kind: 'render3d', assetKey: 'turntablePeach', text: 'SPARKLING VITAMIN DRINK', beats: 8, transition: 'zoom_in'},
    {kind: 'zoomthrough', assetKeys: ['clubNeon', 'poolSplash', 'sunriseRun'], text: 'ÜBERALL *DABEI*', beats: 10, transition: 'cut'},
    {kind: 'lineup', variant: 'grid', beats: 6, transition: 'mask_bars'},
    {kind: 'countdown', text: '3', beats: 5, transition: 'cut'},
    {kind: 'type', text: 'EARLY. FÜR *ALLE*.', beats: 4, transition: 'zoom_in', variant: 'slam'},
    {kind: 'endcard', beats: 10},
  ],
  copy: {
    hook: 'DAS GROSSE FINALE.',
    mid: ['VITAMINE + ELEKTROLYTE', 'ISOTONISCH', 'KALORIENARM'],
    cta: 'DREI SORTEN. *NULL* AUSREDEN.',
  },
  sfxPlan: {
    cues: [
      {name: 'impact_1', beat: 0, volume: 0.9},
      {name: 'fizz_open', beat: 5, volume: 0.6},
      {name: 'riser', beat: 17, volume: 0.6},
      {name: 'impact_2', beat: 23, volume: 0.9},
      {name: 'riser', beat: 47, volume: 0.65},
      {name: 'impact_1', beat: 52, volume: 1},
    ],
    onSceneCut: 'whoosh',
    cutVolume: 0.5,
  },
};
