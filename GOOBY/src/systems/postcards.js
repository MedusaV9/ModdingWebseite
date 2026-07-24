// V6/D2 — postcard-archive engine (PLAN6 Wave D §D2): postcards stop being
// throwaway toasts and become KEEPSAKES. One postcard per FULL day away,
// day boundaries in fixed TRIP ms (day k arrives at bookedAt + k·86400000 —
// never calendar days, so DST changes can never shift, duplicate or drop a
// card), a deterministic per-card text-variant pick (mulberry32, the
// systems/recapDirector.js pickTrack precedent, seeded from the trip's
// destId+bookedAt) and a FIFO archive capped at MAX_ARCHIVE entries (PLAN6
// §5 persistence guardrail: 36).
//
// PURE module — no three.js/DOM imports; node:test drives it directly
// (test/postcards.test.js). The archive itself lives INSIDE the vacation
// save slice (systems/vacation.js `archive` + `lastPostcardDayProcessed` —
// wired through defaultSlice/sliceOf/bookSlice/pickupSlice per the
// whitelist-strip rule); generation runs through processPostcardsUpTo()
// from vacation.tick(), which BOTH the live 1 s ticker (core/timeEngine.js)
// and the boot catch-up (systems/offline.js) call — one shared pure
// processor, so a 5-day app-closed gap produces a byte-identical archive to
// live ticking, without duplicates (the day bookkeeping is monotonic; a
// backwards device-clock jump generates nothing and never double-writes).
//
// Texts: pooled per destination — string keys
// `vacation.postcard.<destId>.<variant>` (variants 1..VARIANTS, EN+DE in
// data/strings/v6-vacation-content.js, following the v5-vacation
// `vacation.postcard.<destId>` key pattern). The legacy single-line keys
// stay untouched for the V5 toast path; the archive rack renders the pooled
// lines through postcardTextKey().

import { getVacation } from '../data/vacations.js';

/** §E0.1-2: the binding postcard-archive numbers — frozen in the owning module. */
export const POSTCARDS = Object.freeze({
  /**
   * One trip "day" in fixed REAL ms. MUST equal systems/vacation.js
   * VACATION.MS_PER_DAY (pinned by test/postcards.test.js — duplicated here
   * only to keep this module import-cycle-free: vacation.js imports us).
   */
  MS_PER_DAY: 86400000,
  /** Archive hard cap (PLAN6 §5): oldest entries drop first (FIFO). */
  MAX_ARCHIVE: 36,
  /** Text-pool size per destination (keys `vacation.postcard.<id>.1..N`). */
  VARIANTS: 3,
});

/**
 * @typedef {Object} PostcardEntry
 * @property {string} destId   catalog id (data/vacations.js)
 * @property {number} dayIndex 1-based full-day-away index within its trip
 * @property {number} variant  1-based text-pool pick (1..VARIANTS)
 * @property {number} atMs     fixed-ms arrival time (bookedAt + dayIndex·day)
 */

/** mulberry32 PRNG — deterministic 0..1 stream from a uint32 seed (the
 * systems/recapDirector.js recipe, verbatim). */
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** FNV-1a string hash → uint32 (destId → seed material, dependency-free). */
function hashStr(str) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < str.length; i += 1) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/**
 * The trip's deterministic seed: destId + booking timestamp. Live ticking,
 * offline catch-up and a reinstall replaying the same save all derive the
 * SAME seed, so every replay yields identical cards.
 * @param {string} destId
 * @param {number} bookedAt epoch ms of the booking
 * @returns {number} uint32
 */
export function tripSeed(destId, bookedAt) {
  const at = Math.floor(Number(bookedAt) || 0);
  return (hashStr(String(destId ?? '')) ^ (at >>> 0)) >>> 0;
}

/**
 * Deterministic text-variant pick for day `dayIndex` of a trip (1-based,
 * 1..VARIANTS). Same (destId, bookedAt, dayIndex) → same variant, always.
 * @param {string} destId
 * @param {number} bookedAt
 * @param {number} dayIndex 1-based full-day index
 * @returns {number} 1..POSTCARDS.VARIANTS
 */
export function variantOf(destId, bookedAt, dayIndex) {
  const k = Math.max(1, Math.floor(Number(dayIndex) || 1));
  // Golden-ratio odd multiplier decorrelates consecutive days off one seed.
  const rnd = mulberry32((tripSeed(destId, bookedAt) ^ Math.imul(k, 0x9e3779b1)) >>> 0);
  return 1 + (Math.floor(rnd() * POSTCARDS.VARIANTS) % POSTCARDS.VARIANTS);
}

/**
 * The strings.js key for an archive entry's handwritten line. Junk variants
 * clamp into the pool (render-time defense — an entry from a future, bigger
 * pool downgrades gracefully instead of breaking the rack).
 * @param {PostcardEntry|{destId?: string, variant?: number}} entry
 * @returns {string} `vacation.postcard.<destId>.<variant>`
 */
export function postcardTextKey(entry) {
  const destId = typeof entry?.destId === 'string' ? entry.destId : '';
  const raw = Math.floor(Number(entry?.variant) || 1);
  const variant = Math.min(POSTCARDS.VARIANTS, Math.max(1, raw));
  return `vacation.postcard.${destId}.${variant}`;
}

/**
 * Normalize ONE raw archive entry (junk → null). Valid entries carry a
 * KNOWN catalog destId (an unknown id has no art/name/pool to render), a
 * 1-based integer dayIndex, a ≥1 integer variant and a finite atMs ≥ 0.
 * @param {unknown} raw
 * @returns {PostcardEntry|null}
 */
export function normalizeEntry(raw) {
  if (raw == null || typeof raw !== 'object') return null;
  const e = /** @type {{destId?: unknown, dayIndex?: unknown, variant?: unknown, atMs?: unknown}} */ (raw);
  const destId = typeof e.destId === 'string' ? e.destId : '';
  if (!destId || !getVacation(destId)) return null;
  const dayIndex = Math.floor(Number(e.dayIndex));
  const variant = Math.floor(Number(e.variant));
  const atMs = Number(e.atMs);
  if (!Number.isFinite(dayIndex) || dayIndex < 1) return null;
  if (!Number.isFinite(variant) || variant < 1) return null;
  if (!Number.isFinite(atMs) || atMs < 0) return null;
  return { destId, dayIndex, variant, atMs };
}

/**
 * Normalize a raw archive array: junk leaves drop, duplicate cards
 * (same destId+atMs+dayIndex) collapse to their first occurrence, entries
 * sort chronologically (stable), and the FIFO cap keeps the NEWEST
 * MAX_ARCHIVE entries. Never mutates the input; always returns a new array.
 * @param {unknown} raw
 * @returns {PostcardEntry[]}
 */
export function normalizeArchive(raw) {
  if (!Array.isArray(raw)) return [];
  /** @type {PostcardEntry[]} */
  const clean = [];
  const seen = new Set();
  for (const item of raw) {
    const entry = normalizeEntry(item);
    if (entry == null) continue;
    const key = `${entry.destId}|${entry.atMs}|${entry.dayIndex}`;
    if (seen.has(key)) continue;
    seen.add(key);
    clean.push(entry);
  }
  clean.sort((a, b) => a.atMs - b.atMs);
  return clean.length > POSTCARDS.MAX_ARCHIVE
    ? clean.slice(clean.length - POSTCARDS.MAX_ARCHIVE)
    : clean;
}

/**
 * THE shared pure processor: bring a vacation slice's postcard archive
 * current to `nowMs`. Day math mirrors systems/vacation.js postcardsDue
 * verbatim (one card per FULL day away, capped at days − 1 — the last day
 * Gooby travels home instead of writing; the clock clamps at returnAt so
 * RETURN_READY/OVERDUE gaps converge on the same archive). Each generated
 * entry is stamped with its fixed-ms arrival time (bookedAt + k·day), NOT
 * the observation clock — that is what makes a live ticker and a single
 * offline catch-up call produce byte-identical archives. The monotonic
 * `lastPostcardDayProcessed` bookkeeping makes generation idempotent and
 * backwards-clock-safe (a regressed clock generates nothing; already-
 * written cards are never re-written).
 * @param {{destId?: string, bookedAt?: number, returnAt?: number,
 *   archive?: unknown, lastPostcardDayProcessed?: number}} v vacation slice
 * @param {number} nowMs
 * @returns {{archive: PostcardEntry[], lastPostcardDayProcessed: number,
 *   added: number}}
 */
export function processPostcardsUpTo(v, nowMs) {
  const archive = normalizeArchive(v?.archive);
  const last = Math.max(0, Math.floor(Number(v?.lastPostcardDayProcessed) || 0));
  const destId = typeof v?.destId === 'string' ? v.destId : '';
  const bookedAt = Number(v?.bookedAt) || 0;
  const returnAt = Number(v?.returnAt) || 0;
  const now = Number(nowMs) || 0;
  if (!destId || !getVacation(destId) || !(bookedAt > 0) || !(returnAt > bookedAt)) {
    return { archive, lastPostcardDayProcessed: last, added: 0 };
  }
  const totalDays = Math.round((returnAt - bookedAt) / POSTCARDS.MS_PER_DAY);
  const maxCards = Math.max(0, totalDays - 1);
  const fullDays = Math.floor((Math.min(now, returnAt) - bookedAt) / POSTCARDS.MS_PER_DAY);
  const due = Math.max(0, Math.min(fullDays, maxCards));
  let added = 0;
  for (let k = last + 1; k <= due; k += 1) {
    archive.push({
      destId,
      dayIndex: k,
      variant: variantOf(destId, bookedAt, k),
      atMs: bookedAt + k * POSTCARDS.MS_PER_DAY,
    });
    added += 1;
  }
  const capped = archive.length > POSTCARDS.MAX_ARCHIVE
    ? archive.slice(archive.length - POSTCARDS.MAX_ARCHIVE)
    : archive;
  return { archive: capped, lastPostcardDayProcessed: Math.max(last, due), added };
}

/**
 * Read the postcard archive off a save state, normalized (the stable read
 * API for UI surfaces — airport rack, album shelf — and for F1's sticker
 * conditions, which are ruled to be pure reads of this archive). Never
 * mutates `state`; junk shapes yield [].
 * @param {object} state save state (or any {vacation?} shape)
 * @returns {PostcardEntry[]} chronological, ≤ MAX_ARCHIVE entries
 */
export function archiveOf(state) {
  return normalizeArchive(state?.vacation?.archive);
}
