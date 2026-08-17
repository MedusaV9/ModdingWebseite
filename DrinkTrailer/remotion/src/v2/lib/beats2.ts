/**
 * V2 beat-grid helpers (60fps).
 *
 * Reads assets/music/v2/beat_grid_v2.json (embedded into the manifest as
 * `beatGridV2Json` by scripts/sync-assets.mjs) with arbitrary track keys.
 * While the v2 music agent has not delivered a track yet, every lookup
 * falls back to the v1 grid (`beatGridJson`: hype_track 140 BPM /
 * clean_track 105 BPM) and finally to a synthetic bpm grid — configs are
 * ALWAYS renderable.
 *
 * Expected beat_grid_v2.json shape (same as the v1 generate_audio.py format,
 * times in seconds):
 *   { "tracks": { "<trackKey>": { "bpm": 140, "first_beat_offset_sec": 0,
 *       "beats_sec": [...], "markers_sec": {"drop1": 6.86, ...},
 *       "duration_sec": 22.0 } } }
 */
import {beatGridJson, beatGridV2Json} from '../../lib/manifest.generated';
import {FPS2} from '../config/types';

export type TrackInfo2 = {
  /** The key this track was resolved under. */
  key: string;
  bpm: number;
  /** Seconds from audio start to beat 0. */
  offsetSeconds: number;
  /** Exact beat timestamps in seconds, when the grid provides them. */
  beatsSec?: number[];
  /** Named markers, seconds from audio start. */
  markers: Record<string, number>;
  /** Track length in seconds when the grid provides it. */
  durationSec?: number;
  /** Where the data came from — useful for debugging. */
  source: 'v2' | 'v1' | 'synthetic';
};

const FALLBACK_BPM: Record<'hype' | 'clean', number> = {hype: 140, clean: 105};

const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);

const parseNumberMap = (raw: unknown): Record<string, number> => {
  const out: Record<string, number> = {};
  if (raw !== null && typeof raw === 'object') {
    for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
      if (isNum(value)) out[key] = value;
    }
  }
  return out;
};

const parseTrack = (key: string, raw: unknown, source: 'v2' | 'v1'): TrackInfo2 | null => {
  if (raw === null || typeof raw !== 'object') return null;
  const t = raw as Record<string, unknown>;
  const bpm = isNum(t.bpm) && t.bpm > 0 ? t.bpm : null;
  if (bpm === null) return null;
  const offset = isNum(t.offsetSeconds)
    ? t.offsetSeconds
    : isNum(t.first_beat_offset_sec)
      ? t.first_beat_offset_sec
      : 0;
  const beats = Array.isArray(t.beats_sec) ? t.beats_sec.filter(isNum) : undefined;
  return {
    key,
    bpm,
    offsetSeconds: offset,
    beatsSec: beats && beats.length > 0 ? beats : undefined,
    markers: {...parseNumberMap(t.markers), ...parseNumberMap(t.markers_sec)},
    durationSec: isNum(t.duration_sec) ? t.duration_sec : undefined,
    source,
  };
};

const parseTracks = (raw: unknown, source: 'v2' | 'v1'): Map<string, TrackInfo2> => {
  const out = new Map<string, TrackInfo2>();
  if (raw === null || typeof raw !== 'object') return out;
  const tracks = (raw as {tracks?: unknown}).tracks;
  if (tracks === null || typeof tracks !== 'object') return out;
  for (const [key, value] of Object.entries(tracks as Record<string, unknown>)) {
    const parsed = parseTrack(key, value, source);
    if (parsed) out.set(key.toLowerCase(), parsed);
  }
  return out;
};

const v2Tracks = parseTracks(beatGridV2Json, 'v2');
const v1Tracks = parseTracks(beatGridJson, 'v1');

const syntheticTrack = (fallback: 'hype' | 'clean'): TrackInfo2 => {
  const bpm = FALLBACK_BPM[fallback];
  const beat = 60 / bpm;
  return {
    key: fallback,
    bpm,
    offsetSeconds: 0,
    markers: {intro: 0, drop1: 16 * beat, drop2: 64 * beat},
    source: 'synthetic',
  };
};

/**
 * Resolve a config's track: v2 grid key → v1 grid (hype_track/clean_track,
 * per `fallback`) → synthetic bpm grid. Matching is case-insensitive.
 */
export const getTrack2 = (
  trackKey: string,
  fallback: 'hype' | 'clean' = 'hype',
): TrackInfo2 => {
  const v2 = v2Tracks.get(trackKey.toLowerCase());
  if (v2) return v2;
  const v1 = v1Tracks.get(`${fallback}_track`) ?? v1Tracks.get(fallback);
  if (v1) return v1;
  return syntheticTrack(fallback);
};

/** Seconds of the n-th beat (exact grid when available, extrapolated past its end). */
export const beatSeconds2 = (track: TrackInfo2, beat: number): number => {
  const beats = track.beatsSec;
  if (beats && beats.length > 0) {
    if (beat < beats.length) {
      const lower = Math.floor(beat);
      const upper = Math.min(lower + 1, beats.length - 1);
      const frac = beat - lower;
      return beats[lower] + (beats[upper] - beats[lower]) * frac;
    }
    const last = beats.length - 1;
    return beats[last] + ((beat - last) * 60) / track.bpm;
  }
  return track.offsetSeconds + (beat * 60) / track.bpm;
};

/** Frame (at 60fps) of the n-th beat of a track. */
export const beatFrame2 = (track: TrackInfo2, beat: number): number =>
  Math.round(beatSeconds2(track, beat) * FPS2);

/** Frames per beat (fractional — round at the call site). */
export const framesPerBeat2 = (track: TrackInfo2): number => (60 / track.bpm) * FPS2;

/** Frame of a named marker, or null when the track has no such marker. */
export const markerFrame2 = (track: TrackInfo2, marker: string): number | null => {
  const seconds = track.markers[marker];
  return isNum(seconds) ? Math.round(seconds * FPS2) : null;
};

/** True once real v2 music/grid data exists for the key (for debug overlays). */
export const hasV2Track = (trackKey: string): boolean =>
  v2Tracks.has(trackKey.toLowerCase());
