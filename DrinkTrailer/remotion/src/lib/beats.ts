/**
 * Beat-grid helpers for cutting on the music.
 *
 * Reads assets/music/beat_grid.json when present (embedded into the manifest
 * by scripts/sync-assets.mjs), otherwise falls back to a synthetic grid:
 * hype = 140 BPM, clean = 104 BPM.
 *
 * Supported beat_grid.json shapes (times in SECONDS from audio start):
 *
 * 1. generate_audio.py format (the one currently produced):
 *    { "tracks": { "hype_track": { "bpm": 140, "first_beat_offset_sec": 0,
 *        "beats_sec": [0, 0.4286, ...], "markers_sec": {"drop1": 6.857, ...} },
 *        "clean_track": {...} } }
 *
 * 2. simple format:
 *    { "tracks": { "hype": { "bpm": 140, "offsetSeconds": 0,
 *        "markers": {"drop1": 6.86} }, "clean": {...} } }
 */
import {FPS} from '../config/timing';
import {beatGridJson} from './manifest.generated';
import type {TrailerStyle} from './assets';

export type BeatGridTrack = {
  bpm: number;
  /** Seconds from audio start to beat 0. */
  offsetSeconds: number;
  /** Named markers, seconds from audio start (audio is placed at frame 0). */
  markers: Record<string, number>;
  /** Exact beat timestamps in seconds, when the grid provides them. */
  beatsSec?: number[];
};

export type BeatGrid = {tracks: Partial<Record<TrailerStyle, BeatGridTrack>>};

export const FALLBACK_BPM: Record<TrailerStyle, number> = {hype: 140, clean: 104};

const fallbackTrack = (style: TrailerStyle): BeatGridTrack => {
  const bpm = FALLBACK_BPM[style];
  const beat = 60 / bpm;
  return {
    bpm,
    offsetSeconds: 0,
    markers: {
      intro: 0,
      drop1: 16 * beat,
      drop2: 64 * beat,
      outro: (style === 'hype' ? 96 : 60) * beat,
    },
  };
};

const isFiniteNumber = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);

const parseNumberMap = (raw: unknown): Record<string, number> | undefined => {
  if (raw === null || typeof raw !== 'object') return undefined;
  const out: Record<string, number> = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (isFiniteNumber(value)) out[key] = value;
  }
  return out;
};

const parseTrack = (raw: unknown): Partial<BeatGridTrack> => {
  if (raw === null || typeof raw !== 'object') return {};
  const t = raw as Record<string, unknown>;
  const out: Partial<BeatGridTrack> = {};
  if (isFiniteNumber(t.bpm) && t.bpm > 0) out.bpm = t.bpm;
  const offset = isFiniteNumber(t.offsetSeconds) ? t.offsetSeconds : t.first_beat_offset_sec;
  if (isFiniteNumber(offset)) out.offsetSeconds = offset;
  const markers = parseNumberMap(t.markers) ?? parseNumberMap(t.markers_sec);
  if (markers) out.markers = markers;
  if (Array.isArray(t.beats_sec)) {
    const beats = t.beats_sec.filter(isFiniteNumber);
    if (beats.length > 0) out.beatsSec = beats;
  }
  return out;
};

const parseGrid = (raw: unknown): BeatGrid => {
  const grid: BeatGrid = {tracks: {}};
  if (raw === null || typeof raw !== 'object') return grid;
  const tracks = (raw as {tracks?: unknown}).tracks;
  if (tracks === null || typeof tracks !== 'object') return grid;
  const trackMap = tracks as Record<string, unknown>;
  for (const style of ['hype', 'clean'] as const) {
    const parsed = parseTrack(trackMap[style] ?? trackMap[`${style}_track`]);
    if (Object.keys(parsed).length > 0) {
      const fallback = fallbackTrack(style);
      grid.tracks[style] = {
        bpm: parsed.bpm ?? fallback.bpm,
        offsetSeconds: parsed.offsetSeconds ?? fallback.offsetSeconds,
        markers: {...fallback.markers, ...parsed.markers},
        beatsSec: parsed.beatsSec,
      };
    }
  }
  return grid;
};

const grid = parseGrid(beatGridJson);

/** The effective beat grid (real file merged over the fallback). */
export const getBeatGrid = (): BeatGrid => ({
  tracks: {
    hype: getTrack('hype'),
    clean: getTrack('clean'),
  },
});

/** The effective track for a style — real data when available, else fallback. */
export const getTrack = (style: TrailerStyle): BeatGridTrack =>
  grid.tracks[style] ?? fallbackTrack(style);

/**
 * Frame of the n-th beat for a given bpm/offset.
 * beatToFrame(4, 140) → frame of beat 4 at 140 BPM.
 */
export const beatToFrame = (
  beat: number,
  bpm: number = FALLBACK_BPM.hype,
  offsetSeconds = 0,
): number => Math.round((offsetSeconds + (beat * 60) / bpm) * FPS);

/**
 * Frame of the n-th beat of a style's track. Uses the exact beats_sec grid
 * when available, otherwise bpm + offset.
 */
export const trackBeatFrame = (style: TrailerStyle, beat: number): number => {
  const track = getTrack(style);
  const exact = track.beatsSec?.[beat];
  if (isFiniteNumber(exact)) return Math.round(exact * FPS);
  return beatToFrame(beat, track.bpm, track.offsetSeconds);
};

/** Frames per beat of a style's track (fractional — round at the call site). */
export const framesPerBeat = (style: TrailerStyle): number =>
  (60 / getTrack(style).bpm) * FPS;

/**
 * Frame of a named marker, e.g. markerFrame('drop1').
 * Markers available in the current grid: intro, drop1, drop2, break, outro,
 * end (hype) / intro, chorus, bridge, outro, end (clean).
 * Unknown markers warn and resolve to frame 0 instead of crashing.
 */
export const markerFrame = (marker: string, style: TrailerStyle = 'hype'): number => {
  const track = getTrack(style);
  const seconds = track.markers[marker];
  if (!isFiniteNumber(seconds)) {
    // eslint-disable-next-line no-console
    console.warn(`[beats] Unknown marker "${marker}" for style "${style}" — returning frame 0.`);
    return 0;
  }
  return Math.round(seconds * FPS);
};
