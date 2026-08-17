import type {TrailerStyleConfig} from '../config/types';

/** 16 — Pastel Collage: Papier-Schnipsel, Scrapbook-Look, rosa Pastellwelt. */
export const style: TrailerStyleConfig = {
  id: 16,
  slug: 'pastel_collage',
  displayName: 'Pastel Collage',
  durationSec: 19,
  track: 'pastel_pop',
  trackFallback: 'clean',
  palette: {bg: '#FBEFF2', ink: '#6B4A55', accent: '#F2A9C4', accent2: '#A8D8C9'},
  fontPreset: 'clean',
  gradePreset: 'pastel',
  effects: ['stickers', 'grain', 'progress_dots'],
  stickers: ['🌸', '🩷', '✨', '🫧'],
  defaultTransition: 'mask_torn',
  structure: [
    {kind: 'collage', assetKeys: ['heroPeach', 'picnic', 'botanical', 'poolSplash'], text: 'SOMMER IM *KOPF*', beats: 10, transition: 'cut'},
    {kind: 'type', text: 'Ausgeschnitten|und aufgeklebt:|dein Lieblingsdrink', beats: 5, variant: 'lines'},
    {kind: 'collage', assetKeys: ['splashPeach', 'sunriseRun', 'studyDesk'], text: 'JEDEN *TAG*', beats: 8},
    {kind: 'endcard', beats: 8},
  ],
  copy: {
    hook: 'Sommer im Kopf.',
    mid: ['Kalorienarm', 'Sparkling Vitamin Drink'],
    cta: 'Kleb dir den *Sommer* ins Leben',
  },
  sfxPlan: {
    cues: [
      {name: 'sparkle_pop', beat: 1, volume: 0.55},
      {name: 'sparkle_pop', beat: 6, volume: 0.55},
      {name: 'sparkle_pop', beat: 17, volume: 0.55},
    ],
    onSceneCut: null,
  },
};
