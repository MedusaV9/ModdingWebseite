/**
 * V2 trailer system — config schema for the 35 vertical trailers
 * ("Early35"). Every trailer is 1080x1920 @ 60fps and is rendered purely
 * from a `TrailerStyleConfig` by src/v2/factory/TrailerFactory.tsx.
 *
 * Style-wave agents: add configs to src/v2/styles/wave_b.ts / wave_c.ts.
 * See src/v2/styles/wave_a.ts for three fully worked reference styles.
 */

// ---------------------------------------------------------------------------
// Format constants (v2 only — v1 stays at 30fps, do not mix)
// ---------------------------------------------------------------------------

export const FPS2 = 60;
export const WIDTH2 = 1080;
export const HEIGHT2 = 1920;

/**
 * Bottom fraction of the frame reserved for TikTok/Reels UI — core copy
 * (hook / mid lines / CTA) must stay ABOVE this zone. The factory's
 * <SafeArea> enforces it; keep custom absolute text above 80% height.
 */
export const BOTTOM_SAFE_FRACTION = 0.2;

// ---------------------------------------------------------------------------
// Presets
// ---------------------------------------------------------------------------

/** Font pairing preset — resolved in src/v2/lib/fonts2.ts. */
export type FontPreset = 'hype' | 'clean' | 'serif' | 'mono' | 'y2k';

/**
 * LUT-like color grade applied over the whole trailer
 * (implemented in src/v2/fx/GradeFilter.tsx):
 *  - none      passthrough
 *  - warm      golden-hour warmth
 *  - cool      teal shadows / crisp highlights
 *  - bw_accent grayscale duotone tinted with palette.accent
 *  - vhs       scanlines + tape wobble + chroma fringe + timestamp
 *  - neon      saturation + bloom glow
 *  - pastel    lifted blacks, soft contrast, milky wash
 *  - noir      hard b/w contrast + vignette + faint accent duotone
 */
export type GradePreset =
  | 'none'
  | 'warm'
  | 'cool'
  | 'bw_accent'
  | 'vhs'
  | 'neon'
  | 'pastel'
  | 'noir';

/**
 * Global overlay/behavior effects, applied for the whole trailer duration.
 * (Per-scene effects are chosen by the scene renderers themselves.)
 */
export type EffectId =
  | 'grain' // subtle animated film grain
  | 'grain_heavy' // strong grain (phonk / vhs looks)
  | 'light_leak' // drifting warm gradient leaks
  | 'film_burn' // burn flashes on scene cuts
  | 'chromatic' // constant slight RGB split, stronger on cuts
  | 'glitch_bursts' // slice-displacement glitches on beats
  | 'letterbox' // cinema bars (2.39:1 inside 9:16)
  | 'shake_on_beat' // impact shake on every 4th beat
  | 'stickers' // emoji sticker layer (uses config.stickers)
  | 'progress_dots' // story progress dots (one per scene)
  | 'progress_bar' // thin progress bar at the top
  | 'hiit_timer' // HIIT-style countdown timer UI
  | 'stop_motion' // frame-quantized playback (~12fps handmade look)
  | 'bloom' // soft screen-blend glow pass over everything
  | 'vignette'; // dark corner vignette

/** How a scene enters (over the tail of the previous scene). */
export type TransitionKind =
  | 'cut'
  | 'whip_left'
  | 'whip_right'
  | 'whip_up'
  | 'zoom_in' // crash-zoom in (radial blur fake)
  | 'zoom_out'
  | 'luma' // luma/exposure fade
  | 'mask_circle'
  | 'mask_bars'
  | 'mask_diagonal' // diagonal wipe
  | 'mask_can' // can-silhouette iris reveal
  | 'mask_torn'; // torn-paper edge reveal

// ---------------------------------------------------------------------------
// Scenes
// ---------------------------------------------------------------------------

/**
 * Scene kinds rendered by the factory:
 *  - hero        full-bleed image + hook line (KineticType)
 *  - splash      punch-zoom image + one big word
 *  - macro       slow close-up (texture/condensation) + small label
 *  - lifestyle   image with pan + one mid-copy line
 *  - lineup      3-flavor lineup (image or tri-panel SplitGrid)
 *  - type        full-screen kinetic typography on palette.bg
 *  - render3d    Blender clip (turntable/dolly/orbit/…) with defensive fallback
 *  - ingredients staggered claim/ingredient list reveal
 *  - countdown   3-2-1 beat-synced number slams
 *  - quote       quote card ("Zitat — Autor" via text)
 *  - split       2-4 images in a SplitGrid (assetKeys, variant '2v'|'3v'|'2x2'|'1+2')
 *  - collage     paper-scrap collage of assetKeys images (CollageCutout)
 *  - beforeafter diagonal wipe between assetKeys[0] (drab) / assetKeys[1] (fresh)
 *  - zoomthrough scene-in-scene infinite zoom through assetKeys images
 *  - endcard     product still + CTA (always forced as last scene)
 */
export type SceneKind =
  | 'hero'
  | 'splash'
  | 'macro'
  | 'lifestyle'
  | 'lineup'
  | 'type'
  | 'render3d'
  | 'ingredients'
  | 'countdown'
  | 'quote'
  | 'split'
  | 'collage'
  | 'beforeafter'
  | 'zoomthrough'
  | 'endcard';

export type SceneSpec = {
  kind: SceneKind;
  /**
   * Image key from IMAGES2 (src/v2/lib/assets2.ts) for image scenes, or a
   * render key from RENDERS2 for 'render3d'. Optional — every kind has a
   * palette-based fallback.
   */
  assetKey?: string;
  /**
   * Image keys for multi-image scenes ('split', 'collage', 'beforeafter',
   * 'zoomthrough'). Missing/unknown keys fall back to palette planes.
   */
  assetKeys?: string[];
  /**
   * Text content: 'type'/'quote' full text ("Zitat — Autor" for quotes),
   * 'countdown' start number ("3"), 'ingredients' items joined with '|'.
   * Falls back to config.copy when omitted.
   */
  text?: string;
  /** Scene length in beats of the config's track (cuts snap to the grid). */
  beats: number;
  /** Transition INTO this scene. Defaults to config.defaultTransition. */
  transition?: TransitionKind;
  /**
   * Free-form per-kind variant hint, e.g. KineticType mode for 'type'
   * ('slam' | 'lines' | 'tracking'), 'grid' for lineup, ….
   */
  variant?: string;
};

// ---------------------------------------------------------------------------
// Audio
// ---------------------------------------------------------------------------

export type SfxCue = {
  /** Substring matched against assets/music/v2 first, then assets/music. */
  name: string;
  /** Beat index on the config's track at which the SFX starts. */
  beat: number;
  volume?: number;
};

export type SfxPlan = {
  cues: SfxCue[];
  /** SFX fired at every scene cut (substring, e.g. 'whoosh'), or null. */
  onSceneCut?: string | null;
  cutVolume?: number;
};

// ---------------------------------------------------------------------------
// Top-level config
// ---------------------------------------------------------------------------

export type PaletteConfig = {
  /** Scene/plate background. */
  bg: string;
  /** Primary text color (must contrast with bg). */
  ink: string;
  /** Primary accent (flashes, highlight words, duotone tint). */
  accent: string;
  /** Secondary accent (gradients, secondary UI). */
  accent2: string;
};

export type CopyConfig = {
  /** Opening hook line (hero/type scene). */
  hook: string;
  /** Mid-roll lines, consumed in order by lifestyle/type/macro scenes. */
  mid: string[];
  /** Endcard claim line above "drinkearly.com • @drink.early". */
  cta: string;
};

export type TrailerStyleConfig = {
  /** 1..35 — see the style table in src/v2/styles/index.ts. */
  id: number;
  /** snake_case, e.g. 'phonk_drift_hype' (used in output filenames). */
  slug: string;
  displayName: string;
  /** 15..40 — duration in seconds (frames = durationSec * 60). */
  durationSec: number;
  /**
   * Track key in assets/music/v2/beat_grid_v2.json. While the v2 music does
   * not exist yet, audio + grid fall back to the v1 track selected by
   * `trackFallback` (default 'hype': 140 BPM; 'clean': 105 BPM).
   */
  track: string;
  trackFallback?: 'hype' | 'clean';
  /** Music gain 0..1 (default 1). */
  musicVolume?: number;
  palette: PaletteConfig;
  fontPreset: FontPreset;
  gradePreset: GradePreset;
  effects: EffectId[];
  /** Used when a scene has no explicit `transition` (default 'cut'). */
  defaultTransition?: TransitionKind;
  /** Emoji stickers for the 'stickers' effect (default set if omitted). */
  stickers?: string[];
  structure: SceneSpec[];
  copy: CopyConfig;
  sfxPlan: SfxPlan;
};

// ---------------------------------------------------------------------------
// Derived helpers
// ---------------------------------------------------------------------------

export const durationInFrames2 = (config: TrailerStyleConfig): number =>
  Math.round(config.durationSec * FPS2);

export const pad2 = (n: number): string => String(n).padStart(2, '0');

/**
 * Remotion composition ID. NOTE: Remotion only allows [a-zA-Z0-9-] in IDs
 * (underscores are rejected by validateCompositionId), so the requested
 * "EarlyV2_<NN>_<name>" scheme becomes dashes: 'hype_phonk' →
 * "EarlyV2-01-hype-phonk". Output files keep underscores (see
 * outputBasename2 / scripts/render-v2.mjs).
 */
export const compositionId2 = (config: TrailerStyleConfig): string =>
  `EarlyV2-${pad2(config.id)}-${config.slug.replace(/_/g, '-')}`;

/** Basename of the rendered file: early_v2_{NN}_{slug}_9x16_60 */
export const outputBasename2 = (config: TrailerStyleConfig): string =>
  `early_v2_${pad2(config.id)}_${config.slug}_9x16_60`;

/** Endcard CTA footer — identical across all 35 trailers. */
export const CTA_LINE = 'drinkearly.com • @drink.early';
