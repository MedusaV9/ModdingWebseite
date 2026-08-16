/**
 * Typed, defensive access to everything under DrinkTrailer/assets/.
 *
 * Files are synced to public/assets/ by scripts/sync-assets.mjs (runs via npm
 * pre-scripts) and served through Remotion's staticFile(). The generated
 * manifest tells us which files actually exist, so music tracks and Blender
 * renders that have not been produced yet NEVER crash a composition — callers
 * receive `null` and render a fallback color plane instead (see
 * src/shared/SmartMedia.tsx and KenBurnsImage's `src={null}` handling).
 */
import {staticFile} from 'remotion';
import {assetFiles} from './manifest.generated';

const fileSet = new Set<string>(assetFiles);

/** True if `relativePath` (e.g. "images/early_lineup_16x9.png") was synced. */
export const hasAsset = (relativePath: string): boolean => fileSet.has(relativePath);

/** staticFile() URL for a manifest-relative path. Only call for existing assets. */
export const assetSrc = (relativePath: string): string => staticFile(`assets/${relativePath}`);

/** All synced files under a top-level dir ("images" | "music" | "renders" | "fonts"). */
export const listAssets = (dir: 'images' | 'music' | 'renders' | 'fonts'): string[] =>
  assetFiles.filter((f) => f.startsWith(`${dir}/`));

// ---------------------------------------------------------------------------
// Images (all present in DrinkTrailer/assets/images/)
// ---------------------------------------------------------------------------

export const IMAGES = {
  bubblesUnderwater9x16: 'images/early_bubbles_underwater_9x16.png',
  heroGrapefruit9x16: 'images/early_hero_grapefruit_9x16.png',
  heroLemonMint9x16: 'images/early_hero_lemonmint_9x16.png',
  heroPeach9x16: 'images/early_hero_peach_9x16.png',
  lifestyleFriends16x9: 'images/early_lifestyle_friends_16x9.png',
  lifestyleGym9x16: 'images/early_lifestyle_gym_9x16.png',
  lineup16x9: 'images/early_lineup_16x9.png',
  lineup9x16: 'images/early_lineup_9x16.png',
  macroCondensation9x16: 'images/early_macro_condensation_9x16.png',
  minimalFloat16x9: 'images/early_minimal_float_16x9.png',
  minimalFloat9x16: 'images/early_minimal_float_9x16.png',
  pourGlass9x16: 'images/early_pour_glass_9x16.png',
  splashGrapefruit16x9: 'images/early_splash_grapefruit_16x9.png',
  splashLemonMint9x16: 'images/early_splash_lemonmint_9x16.png',
  splashPeach9x16: 'images/early_splash_peach_9x16.png',
} as const satisfies Record<string, string>;

export type ImageKey = keyof typeof IMAGES;

/** staticFile() URL for an image, or null if the file is (unexpectedly) missing. */
export const imageSrc = (key: ImageKey): string | null =>
  hasAsset(IMAGES[key]) ? assetSrc(IMAGES[key]) : null;

// ---------------------------------------------------------------------------
// Music + SFX (dropped into assets/music/ by the audio pipeline)
//
// Current real files: hype_track.wav/.m4a, clean_track.wav/.m4a,
// SFX = whoosh_1..3.wav, impact_1..2.wav, fizz_open.wav, riser_short.wav,
// sparkle_pop.wav, ui_tick.wav, plus beat_grid.json (see lib/beats.ts).
// Rule: audio files containing "track" are music tracks, everything else SFX.
// ---------------------------------------------------------------------------

export type TrailerStyle = 'hype' | 'clean';

const AUDIO_EXT = /\.(mp3|wav|m4a|aac|ogg)$/i;

const isTrack = (file: string): boolean => file.toLowerCase().includes('track');

/**
 * staticFile() URL of the music track for a style, or null if none exists yet.
 * Prefers compressed formats (.m4a/.mp3) over .wav when both are present.
 */
export const findMusicTrack = (style: TrailerStyle): string | null => {
  const candidates = listAssets('music').filter(
    (f) => AUDIO_EXT.test(f) && isTrack(f) && f.toLowerCase().includes(style),
  );
  if (candidates.length === 0) return null;
  const compressed = candidates.find((f) => /\.(m4a|mp3|aac|ogg)$/i.test(f));
  return assetSrc(compressed ?? candidates[0]);
};

/** staticFile() URL of an SFX (matched by substring, e.g. "whoosh_1"), or null. */
export const findSfx = (name: string): string | null => {
  const sfx = listAssets('music').filter((f) => AUDIO_EXT.test(f) && !isTrack(f));
  const match = sfx.find((f) => f.toLowerCase().includes(name.toLowerCase()));
  return match ? assetSrc(match) : null;
};

// ---------------------------------------------------------------------------
// Blender renders (may not exist yet — expected as renders/early_<name>.mp4)
// ---------------------------------------------------------------------------

const VIDEO_EXT = /\.(mp4|webm|mov)$/i;

/**
 * staticFile() URL of a render clip, or null if it does not exist yet.
 * Tries `renders/<name>.mp4` / `renders/early_<name>.mp4` exactly, then a
 * substring match over all video files in renders/.
 */
export const renderSrc = (name: string): string | null => {
  const exact = [`renders/${name}.mp4`, `renders/early_${name}.mp4`].find(hasAsset);
  if (exact) return assetSrc(exact);
  const clips = listAssets('renders').filter((f) => VIDEO_EXT.test(f));
  const match = clips.find((f) => f.toLowerCase().includes(name.toLowerCase()));
  return match ? assetSrc(match) : null;
};

/** All available render clips (staticFile URLs), e.g. for montage filling. */
export const listRenderClips = (): string[] =>
  listAssets('renders')
    .filter((f) => VIDEO_EXT.test(f))
    .map(assetSrc);
