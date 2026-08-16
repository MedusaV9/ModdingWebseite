/**
 * Central timing constants for all four EARLY trailers.
 * Compositions in src/Root.tsx read their durationInFrames from here —
 * change durations in this file only.
 */

export const FPS = 30;

/** Total length of the hype trailers (TikTok + Landscape). */
export const HYPE_DURATION_SECONDS = 48;
/** Total length of the clean trailers (TikTok + Landscape). */
export const CLEAN_DURATION_SECONDS = 42;

export const secondsToFrames = (seconds: number): number => Math.round(seconds * FPS);

export const HYPE_DURATION_IN_FRAMES = secondsToFrames(HYPE_DURATION_SECONDS); // 1440
export const CLEAN_DURATION_IN_FRAMES = secondsToFrames(CLEAN_DURATION_SECONDS); // 1260

/** Scene boundaries used by the base implementations (style agents may retune). */
export const HYPE_INTRO_SECONDS = 3.5;
export const HYPE_OUTRO_SECONDS = 6;

export const CLEAN_OPENING_SECONDS = 6;
export const CLEAN_OUTRO_SECONDS = 7;
/** Crossfade length between the clean product scenes. */
export const CLEAN_CROSSFADE_SECONDS = 1;
