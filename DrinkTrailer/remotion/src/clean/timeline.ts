/**
 * Music-locked scene boundaries for the clean trailers.
 *
 * clean_track: 105 BPM, 47 s, markers chorus 9.143 s / bridge 27.429 s /
 * outro 36.571 s. Every scene change sits on a downbeat (bar = 4 beats):
 *
 *   frame 0     intro     — off-white typography opening
 *   frame 274   chorus    — first full product view (Blender dolly + fizz_open)
 *   frame 411   beat 24   — chapter 1: Pfirsich
 *   frame 549   beat 32   — chapter 2: Grapefruit
 *   frame 686   beat 40   — chapter 3: Zitrone-Minze
 *   frame 823   bridge    — macro condensation texture beat
 *   frame 960   beat 56   — benefits recap on cream
 *   frame 1097  outro     — lineup finale + quiet CTA
 *   frame 1260  end of composition (track keeps going → 60-frame audio fade)
 */
import {Easing, interpolate} from 'remotion';
import {CLEAN_DURATION_IN_FRAMES, secondsToFrames} from '../config/timing';
import {markerFrame, trackBeatFrame} from '../lib/beats';

export const CLEAN_T = {
  chorus: markerFrame('chorus', 'clean'),
  chapter1: trackBeatFrame('clean', 24),
  chapter2: trackBeatFrame('clean', 32),
  chapter3: trackBeatFrame('clean', 40),
  bridge: markerFrame('bridge', 'clean'),
  benefits: trackBeatFrame('clean', 56),
  outro: markerFrame('outro', 'clean'),
  end: CLEAN_DURATION_IN_FRAMES,
} as const;

/** Frames the color wipe needs to fully cover the screen (before a downbeat). */
export const WIPE_IN_FRAMES = 14;
/** Frames the color wipe needs to sweep off again (after a downbeat). */
export const WIPE_OUT_FRAMES = 20;
/** Length of the quiet crossfades into macro / benefits / outro. */
export const SCENE_FADE_FRAMES = 16;

/**
 * Musical ending instead of a hard cut (track is 47 s, composition 42 s):
 * duck gently from the outro marker, then ease all the way to silence
 * between ~39.5 s and ~41.8 s. All SFX finish before the fade window.
 */
const FADE_DUCK_LEVEL = 0.78;
const FADE_SILENT_START = secondsToFrames(39.5); // 1185
const FADE_SILENT_END = secondsToFrames(41.8); // 1254

export const cleanMusicVolume = (frame: number): number => {
  if (frame < CLEAN_T.outro) return 1;
  if (frame < FADE_SILENT_START) {
    return interpolate(frame, [CLEAN_T.outro, FADE_SILENT_START], [1, FADE_DUCK_LEVEL], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
      easing: Easing.inOut(Easing.sin),
    });
  }
  return interpolate(frame, [FADE_SILENT_START, FADE_SILENT_END], [FADE_DUCK_LEVEL, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.sin),
  });
};
