/**
 * Beat-derived timeline for the two hype trailers.
 *
 * All values are absolute frames on the 48s/30fps composition, computed from
 * the real hype_track beat grid (140 BPM):
 *   drop1 6.857s → 206 | break 20.571s → 617 | drop2 27.429s → 823 |
 *   outro 41.143s → 1234 | end 48s → 1440
 */
import {markerFrame, trackBeatFrame} from '../lib/beats';

/** Frame of the n-th beat of the hype track (exact grid, not bpm math). */
export const B = (beat: number): number => trackBeatFrame('hype', beat);

export const DROP1 = markerFrame('drop1', 'hype'); // 206 (beat 16)
export const BREAK = markerFrame('break', 'hype'); // 617 (beat 48)
export const DROP2 = markerFrame('drop2', 'hype'); // 823 (beat 64)
export const OUTRO = markerFrame('outro', 'hype'); // 1234 (beat 96)

/** riser_short is 1.3s (39 frames) — start it so it peaks exactly on a drop. */
export const RISER_FRAMES = 39;

/** TikTok safe zone: keep important copy out of the bottom ~15% (and top bar). */
export const TIKTOK_BOTTOM_SAFE = 300;

export type Cut = {
  /** Absolute start frame. */
  from: number;
  /** Cut length in frames. */
  duration: number;
};

/**
 * Slices the range [fromBeat, toBeat) into cuts of `beatsPerCut` beats,
 * snapped to the exact beat grid — the backbone of every montage.
 */
export const beatCuts = (fromBeat: number, toBeat: number, beatsPerCut: number): Cut[] => {
  const cuts: Cut[] = [];
  for (let b = fromBeat; b < toBeat; b += beatsPerCut) {
    const from = B(b);
    const to = B(Math.min(b + beatsPerCut, toBeat));
    cuts.push({from, duration: to - from});
  }
  return cuts;
};
