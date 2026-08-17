/**
 * V2 typed asset access. Builds on the read-only low-level helpers from
 * src/lib/assets.ts (hasAsset/assetSrc/listAssets over the generated
 * manifest) — v1 files are NOT modified.
 *
 * Everything here is defensive: missing files yield `null`, never a crash,
 * so wave_b/wave_c styles can reference future renders/music today.
 */
import {assetSrc, hasAsset, listAssets} from '../../lib/assets';

// ---------------------------------------------------------------------------
// Images — every file in DrinkTrailer/assets/images/. All 9:16 unless the
// key ends in `16x9`.
// ---------------------------------------------------------------------------

export const IMAGES2 = {
  botanical: 'images/early_botanical_9x16.png',
  bubblesUnderwater: 'images/early_bubbles_underwater_9x16.png',
  clubNeon: 'images/early_club_neon_9x16.png',
  epicSmoke: 'images/early_epic_smoke_9x16.png',
  gymChalk: 'images/early_gym_chalk_9x16.png',
  heroGrapefruit: 'images/early_hero_grapefruit_9x16.png',
  heroLemonMint: 'images/early_hero_lemonmint_9x16.png',
  heroPeach: 'images/early_hero_peach_9x16.png',
  lifestyleFriends16x9: 'images/early_lifestyle_friends_16x9.png',
  lifestyleGym: 'images/early_lifestyle_gym_9x16.png',
  lineup: 'images/early_lineup_9x16.png',
  lineup16x9: 'images/early_lineup_16x9.png',
  macroCondensation: 'images/early_macro_condensation_9x16.png',
  minimalFloat: 'images/early_minimal_float_9x16.png',
  minimalFloat16x9: 'images/early_minimal_float_16x9.png',
  picnic: 'images/early_picnic_9x16.png',
  poolSplash: 'images/early_pool_splash_9x16.png',
  pourGlass: 'images/early_pour_glass_9x16.png',
  splashGrapefruit16x9: 'images/early_splash_grapefruit_16x9.png',
  splashLemonMint: 'images/early_splash_lemonmint_9x16.png',
  splashPeach: 'images/early_splash_peach_9x16.png',
  studyDesk: 'images/early_study_desk_9x16.png',
  sunriseRun: 'images/early_sunrise_run_9x16.png',
} as const satisfies Record<string, string>;

export type ImageKey2 = keyof typeof IMAGES2;

export const isImageKey2 = (key: string): key is ImageKey2 => key in IMAGES2;

/** staticFile() URL for an image key, or null if the file is missing. */
export const imageSrc2 = (key: ImageKey2 | string | undefined): string | null => {
  if (!key || !isImageKey2(key)) return null;
  return hasAsset(IMAGES2[key]) ? assetSrc(IMAGES2[key]) : null;
};

// ---------------------------------------------------------------------------
// Blender product renders. turntable/dolly exist today; orbit/crash/rise/
// overhead are FUTURE clips — keys already resolve defensively (null until
// the files land in assets/renders/).
// ---------------------------------------------------------------------------

/** Key → substrings tried (in order) against video files in renders/. */
export const RENDERS2 = {
  turntablePeach: ['turntable_peach', 'turntable'],
  dollyPeach16x9: ['dolly_peach', 'dolly'],
  orbitPeach: ['orbit_peach', 'orbit'],
  orbitGrapefruit: ['orbit_grapefruit'],
  orbitLemonMint: ['orbit_lemonmint', 'orbit_lemon'],
  crashZoom: ['crash'],
  riseCan: ['rise'],
  overheadLineup: ['overhead'],
} as const satisfies Record<string, readonly string[]>;

export type RenderKey2 = keyof typeof RENDERS2;

const VIDEO_EXT = /\.(mp4|webm|mov)$/i;

const renderVideos = (): string[] => listAssets('renders').filter((f) => VIDEO_EXT.test(f));

/**
 * staticFile() URL for a render key (or raw substring), or null while the
 * clip has not been produced yet.
 */
export const renderSrc2 = (key: RenderKey2 | string | undefined): string | null => {
  if (!key) return null;
  const needles: readonly string[] =
    key in RENDERS2 ? RENDERS2[key as RenderKey2] : [key.toLowerCase()];
  const clips = renderVideos();
  for (const needle of needles) {
    const match = clips.find((f) => f.toLowerCase().includes(needle));
    if (match) return assetSrc(match);
  }
  return null;
};

/** Product still (Blender PNG) for a flavor — used on endcards. */
export const productStill2 = (
  flavor: 'peach' | 'grapefruit' | 'lemonmint' = 'peach',
): string | null => {
  const rel = `renders/early_still_${flavor}_9x16.png`;
  return hasAsset(rel) ? assetSrc(rel) : null;
};

// ---------------------------------------------------------------------------
// Music (v2 with v1 fallback) + SFX. The v2 music agent will drop files into
// assets/music/v2/ (synced as manifest paths "music/v2/…").
// ---------------------------------------------------------------------------

const AUDIO_EXT = /\.(mp3|wav|m4a|aac|ogg)$/i;

const audioFiles = (): string[] => listAssets('music').filter((f) => AUDIO_EXT.test(f));

const preferCompressed = (candidates: string[]): string | null => {
  if (candidates.length === 0) return null;
  return candidates.find((f) => /\.(m4a|mp3|aac|ogg)$/i.test(f)) ?? candidates[0];
};

/**
 * staticFile() URL of the music file for a v2 track key: exact/substring
 * match inside music/v2/ first, then the v1 fallback track ('hype'/'clean').
 */
export const musicSrc2 = (
  trackKey: string,
  fallback: 'hype' | 'clean' = 'hype',
): string | null => {
  const needle = trackKey.toLowerCase();
  const v2 = audioFiles().filter(
    (f) => f.startsWith('music/v2/') && f.toLowerCase().includes(needle),
  );
  const v2Pick = preferCompressed(v2);
  if (v2Pick) return assetSrc(v2Pick);

  const v1 = audioFiles().filter(
    (f) =>
      !f.startsWith('music/v2/') &&
      f.toLowerCase().includes('track') &&
      f.toLowerCase().includes(fallback),
  );
  const v1Pick = preferCompressed(v1);
  return v1Pick ? assetSrc(v1Pick) : null;
};

/**
 * staticFile() URL of an SFX matched by substring — searches music/v2/
 * first, then the v1 SFX pool (whoosh_1..3, impact_1..2, fizz_open,
 * riser_short, sparkle_pop, ui_tick).
 */
export const sfxSrc2 = (name: string): string | null => {
  const needle = name.toLowerCase();
  const pool = audioFiles().filter((f) => !f.toLowerCase().includes('track'));
  const v2Match = pool.find((f) => f.startsWith('music/v2/') && f.toLowerCase().includes(needle));
  if (v2Match) return assetSrc(v2Match);
  const v1Match = pool.find((f) => !f.startsWith('music/v2/') && f.toLowerCase().includes(needle));
  return v1Match ? assetSrc(v1Match) : null;
};
