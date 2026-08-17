/**
 * WAVE A — three fully worked reference styles. These define the quality
 * bar for wave_b/wave_c: every style must fill palette/font/grade/effects/
 * structure/copy/sfxPlan completely and its structure beats should sum to
 * durationSec / (60 / bpm) of the fallback track (hype 140 → 0.4286s/beat,
 * clean 105 → 0.5714s/beat) so cuts land on the grid.
 */
import type {TrailerStyleConfig} from '../config/types';

export const WAVE_A: TrailerStyleConfig[] = [
  // ── 01 · PHONK DRIFT HYPE ────────────────────────────────────────────
  // Aggressive b/w phonk edit: red accent duotone, whip cuts, RGB pulses,
  // glitch bursts, camera impacts. 42 beats @140 = 18.0s.
  {
    id: 1,
    slug: 'phonk_drift_hype',
    displayName: 'Phonk Drift Hype',
    durationSec: 18,
    track: 'phonk_140',
    trackFallback: 'hype',
    musicVolume: 1,
    palette: {bg: '#0B0B0F', ink: '#F2EEE6', accent: '#FF3B3B', accent2: '#8A7CFF'},
    fontPreset: 'hype',
    gradePreset: 'bw_accent',
    effects: ['grain_heavy', 'chromatic', 'glitch_bursts', 'shake_on_beat', 'letterbox', 'vignette'],
    defaultTransition: 'whip_left',
    structure: [
      {kind: 'hero', assetKey: 'heroPeach', beats: 6},
      {kind: 'splash', assetKey: 'splashPeach', text: '*BOOM.*', beats: 4, transition: 'whip_left'},
      {kind: 'type', text: 'NO *SUGAR.* NO LIMITS.', beats: 4, transition: 'zoom_in', variant: 'slam'},
      {kind: 'macro', assetKey: 'macroCondensation', beats: 4, transition: 'whip_right'},
      {kind: 'render3d', assetKey: 'turntablePeach', beats: 8, transition: 'zoom_in'},
      {kind: 'lineup', beats: 6, transition: 'whip_up', variant: 'grid'},
      {kind: 'endcard', beats: 10, transition: 'luma'},
    ],
    copy: {
      hook: 'ZU FRÜH? *GIBT’S NICHT.*',
      mid: ['KALT. LAUT. *WACH.*', 'DREI SORTEN. *EIN MODUS.*'],
      cta: 'GET *EARLY.*',
    },
    sfxPlan: {
      cues: [
        {name: 'riser', beat: 15, volume: 0.9},
        {name: 'impact_1', beat: 18, volume: 1},
        {name: 'impact_2', beat: 26, volume: 0.85},
        {name: 'fizz_open', beat: 32, volume: 0.9},
      ],
      onSceneCut: 'whoosh',
      cutVolume: 0.5,
    },
  },

  // ── 02 · APPLE AIR 60 ────────────────────────────────────────────────
  // Ultra-clean product film: cream pastel grade, tracking-expand type,
  // luma fades only, near-zero FX. 35 beats @105 = 20.0s.
  {
    id: 2,
    slug: 'apple_air_60',
    displayName: 'Apple Air 60',
    durationSec: 20,
    track: 'air_ambient_100',
    trackFallback: 'clean',
    musicVolume: 0.9,
    palette: {bg: '#F7F3ED', ink: '#1D1D1F', accent: '#D98E8E', accent2: '#F2AC8F'},
    fontPreset: 'clean',
    gradePreset: 'pastel',
    effects: ['grain'],
    defaultTransition: 'luma',
    structure: [
      {kind: 'type', text: 'Leicht. Eiskalt. EARLY.', beats: 6, variant: 'tracking'},
      {kind: 'hero', assetKey: 'minimalFloat', beats: 6},
      {kind: 'macro', assetKey: 'macroCondensation', text: 'Feine Perlage. Echte Vitamine.', beats: 5},
      {kind: 'lifestyle', assetKey: 'picnic', beats: 6},
      {kind: 'render3d', assetKey: 'turntablePeach', text: 'SPARKLING VITAMIN DRINK', beats: 6},
      {kind: 'endcard', beats: 6},
    ],
    copy: {
      hook: 'Erfrischung. *Neu* gedacht.',
      mid: ['Für Momente, die zählen.'],
      cta: 'Mach’s dir *early.*',
    },
    sfxPlan: {
      cues: [
        {name: 'sparkle_pop', beat: 6, volume: 0.5},
        {name: 'fizz_open', beat: 17, volume: 0.45},
      ],
      onSceneCut: null,
    },
  },

  // ── 03 · VHS RETRO ───────────────────────────────────────────────────
  // Camcorder summer tape: VHS grade (wobble/scanlines/timecode), mono HUD
  // type, light leaks, glitch tracking errors. 35 beats @105 = 20.0s.
  {
    id: 3,
    slug: 'vhs_retro',
    displayName: 'VHS Retro',
    durationSec: 20,
    track: 'retro_wave_110',
    trackFallback: 'clean',
    musicVolume: 1,
    palette: {bg: '#14101E', ink: '#F4E9D8', accent: '#FF6EC7', accent2: '#4DE3FF'},
    fontPreset: 'mono',
    gradePreset: 'vhs',
    effects: ['grain_heavy', 'light_leak', 'glitch_bursts'],
    defaultTransition: 'cut',
    structure: [
      {kind: 'hero', assetKey: 'poolSplash', beats: 6},
      {kind: 'lifestyle', assetKey: 'sunriseRun', beats: 5, transition: 'whip_right'},
      {kind: 'splash', assetKey: 'splashLemonMint', text: '100% VIBES', beats: 4, transition: 'whip_left'},
      {kind: 'macro', assetKey: 'bubblesUnderwater', beats: 5, transition: 'cut'},
      {kind: 'countdown', text: '3', beats: 3, transition: 'cut'},
      {kind: 'lineup', beats: 5, transition: 'zoom_in', variant: 'grid'},
      {kind: 'endcard', beats: 7, transition: 'luma'},
    ],
    copy: {
      hook: 'REWIND *THE SUMMER*',
      mid: ['AUFNAHME LÄUFT.', 'GESCHMACK AUF VHS.'],
      cta: 'BE KIND. *DRINK EARLY.*',
    },
    sfxPlan: {
      cues: [
        {name: 'fizz_open', beat: 0, volume: 0.7},
        {name: 'riser', beat: 20, volume: 0.8},
        {name: 'impact_1', beat: 23, volume: 0.9},
        {name: 'sparkle_pop', beat: 28, volume: 0.6},
      ],
      onSceneCut: 'whoosh',
      cutVolume: 0.45,
    },
  },
];
