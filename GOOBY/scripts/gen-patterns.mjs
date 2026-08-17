#!/usr/bin/env node
// GOOBY V6/A2 — seamless screen-theme pattern-tile generator (PLAN6 Wave A).
//
// Pure Node, zero deps: renders eleven 512×512 two-tone motif tiles (one per
// screen theme) into INDEXED (color type 3) PNGs and writes them to
// public/assets/acui/pattern_<theme>.png. The CRC32 helper is imported from
// the sibling gen-icons.mjs encoder; the SDF toolkit below is an adapted copy
// of its rasterizer (gen-icons keeps its shape factories module-private).
//
// Hard guarantees (asserted at generation time AND re-checked by
// test/screenThemes.test.js):
//   - seamless BY MATH: every stamp writes through wrap-around indices
//     (motif positions wrap modulo the tile size), verified per theme by
//     re-rendering with all content shifted (137, 289) px and comparing
//     against the torus-rolled original — any accidental edge clipping or
//     missing wrap breaks the equality;
//   - low contrast: both ink tones are mixed toward the theme background so
//     every palette entry stays within a 6 % luminance delta of the base
//     (palette index 0 is always the background color);
//   - budget: each tile ≤ 48 KiB, the 11-tile aggregate ≤ 512 KiB
//     (PLAN6 hard budget guardrails — image payload).
//
// Determinism: placements come from a per-theme seeded mulberry32 stream, so
// re-runs are byte-stable.
//
// Run (from GOOBY/):  node scripts/gen-patterns.mjs

import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { crc32 } from './gen-icons.mjs';

// ---------------------------------------------------------------------------
// Frozen numbers (PLAN6 §Hard budget guardrails / A2 acceptance)
// ---------------------------------------------------------------------------

export const TILE = 512; // tile edge (px)
export const MAX_TILE_BYTES = 48 * 1024; // ≤48 KiB per tile
export const MAX_AGGREGATE_BYTES = 512 * 1024; // ≤512 KiB for all 11
export const MAX_LUMA_DELTA = 0.06 * 255; // ≤6 % luminance delta vs base

// ---------------------------------------------------------------------------
// Indexed PNG encoder (color type 3; bit depth 4 — the palette is ≤16)
// ---------------------------------------------------------------------------

/**
 * Build one PNG chunk: length + type + data + CRC (same shape as
 * gen-icons.mjs' private pngChunk — copied because it is not exported).
 * @param {string} type 4-char chunk type
 * @param {Buffer} data
 * @returns {Buffer}
 */
function pngChunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, 'ascii');
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

/**
 * Encode a palette-indexed image as a PNG (color type 3). Bit depth 4 when
 * the palette fits in 16 entries (it always does here: 4×4 quantized tone
 * levels), else 8. Filter None on every row; deflate level 9.
 * @param {number} size square edge (px)
 * @param {Uint8Array} indices `size * size` palette indices
 * @param {Array<[number, number, number]>} palette RGB triplets (≤256)
 * @returns {Buffer} complete PNG file bytes
 */
export function encodeIndexedPng(size, indices, palette) {
  if (indices.length !== size * size) {
    throw new Error(`encodeIndexedPng: expected ${size * size} indices, got ${indices.length}`);
  }
  if (palette.length > 256) throw new Error(`encodeIndexedPng: palette too large (${palette.length})`);
  const depth = palette.length <= 16 ? 4 : 8;
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = depth;
  ihdr[9] = 3; // color type 3 = indexed
  // bytes 10–12 stay 0: deflate compression, adaptive filter, no interlace
  const plte = Buffer.alloc(palette.length * 3);
  palette.forEach(([r, g, b], i) => {
    plte[i * 3] = r;
    plte[i * 3 + 1] = g;
    plte[i * 3 + 2] = b;
  });
  const stride = depth === 4 ? size / 2 : size;
  const raw = Buffer.alloc((stride + 1) * size);
  for (let y = 0; y < size; y++) {
    const pos = y * (stride + 1);
    raw[pos] = 0; // filter: None
    if (depth === 4) {
      for (let x = 0; x < size; x += 2) {
        raw[pos + 1 + x / 2] = (indices[y * size + x] << 4) | indices[y * size + x + 1];
      }
    } else {
      raw.set(indices.subarray(y * size, (y + 1) * size), pos + 1);
    }
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk('IHDR', ihdr),
    pngChunk('PLTE', plte),
    pngChunk('IDAT', deflateSync(raw, { level: 9 })),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

/** @param {string} hex `#RRGGBB` @returns {[number, number, number]} */
function rgb(hex) {
  return [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
}

/** Rec. 709 luma of an RGB triplet (0–255). @param {[number,number,number]} c */
function luma(c) {
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

/** Linear mix a→b by k. @returns {[number, number, number]} */
function mix(a, b, k) {
  return [0, 1, 2].map((i) => Math.round(a[i] + (b[i] - a[i]) * k));
}

/**
 * Derive an ink tone: mix the hue color toward the background until its luma
 * sits exactly `delta` (8-bit units) away from the background luma — this is
 * what makes the ≤6 % contrast rule hold by construction.
 * @param {[number,number,number]} bg
 * @param {[number,number,number]} hue full-strength hue source (e.g. accent)
 * @param {number} delta target |luma - bgLuma| in 0–255 units
 * @returns {[number, number, number]}
 */
function toneFor(bg, hue, delta) {
  const span = Math.abs(luma(hue) - luma(bg));
  const k = span < 1 ? 1 : Math.min(1, delta / span);
  return mix(bg, hue, k);
}

// ---------------------------------------------------------------------------
// SDF toolkit (adapted from gen-icons.mjs' rasterizer; d ≤ 0 inside)
// ---------------------------------------------------------------------------

/** @typedef {(x: number, y: number) => number} Sdf */

/** @type {(cx:number,cy:number,r:number)=>Sdf} */
const circle = (cx, cy, r) => (x, y) => Math.hypot(x - cx, y - cy) - r;

/** Ring (annulus) of radius r, half-thickness t. @type {(cx:number,cy:number,r:number,t:number)=>Sdf} */
const ring = (cx, cy, r, t) => (x, y) => Math.abs(Math.hypot(x - cx, y - cy) - r) - t;

/** Axis-aligned ellipse (scaled-distance approximation, fine for AA). */
const ellipse = (cx, cy, rx, ry) => (x, y) => {
  const k = Math.hypot((x - cx) / rx, (y - cy) / ry);
  return (k - 1) * Math.min(rx, ry);
};

/** Capsule: segment (ax, ay)→(bx, by) with radius r. */
const capsule = (ax, ay, bx, by, r) => (x, y) => {
  const pax = x - ax, pay = y - ay, bax = bx - ax, bay = by - ay;
  const h = Math.min(1, Math.max(0, (pax * bax + pay * bay) / (bax * bax + bay * bay)));
  return Math.hypot(pax - bax * h, pay - bay * h) - r;
};

/** Rounded rectangle centered (cx, cy), half-size (hx, hy), corner radius r. */
const roundRect = (cx, cy, hx, hy, r) => (x, y) => {
  const qx = Math.abs(x - cx) - (hx - r);
  const qy = Math.abs(y - cy) - (hy - r);
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
};

/** Rounded-rectangle OUTLINE (half line thickness t). */
const rrRing = (cx, cy, hx, hy, r, t) => {
  const f = roundRect(cx, cy, hx, hy, r);
  return (x, y) => Math.abs(f(x, y)) - t;
};

/** Simple polygon (any winding, non-convex OK — iq's sdPolygon). */
const poly = (pts) => (x, y) => {
  let d = Infinity;
  let s = 1;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i];
    const [xj, yj] = pts[j];
    const ex = xj - xi, ey = yj - yi;
    const wx = x - xi, wy = y - yi;
    const t = Math.min(1, Math.max(0, (wx * ex + wy * ey) / (ex * ex + ey * ey)));
    const bx = wx - ex * t, by = wy - ey * t;
    d = Math.min(d, bx * bx + by * by);
    const c1 = y >= yi, c2 = y < yj, c3 = ex * wy > ey * wx;
    if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
  }
  return s * Math.sqrt(d);
};

/** n-pointed star polygon (outer radius r, inner radius ri), point up. */
const star = (n, r, ri) => {
  const pts = [];
  for (let k = 0; k < 2 * n; k++) {
    const a = (k * Math.PI) / n - Math.PI / 2;
    const rad = k % 2 === 0 ? r : ri;
    pts.push([rad * Math.cos(a), rad * Math.sin(a)]);
  }
  return poly(pts);
};

/** Circular arc stroke: radius r from angle a0→a1 (radians), half-width t. */
const arc = (cx, cy, r, a0, a1, t) => (x, y) => {
  const twoPi = Math.PI * 2;
  let rel = Math.atan2(y - cy, x - cx) - a0;
  rel = ((rel % twoPi) + twoPi) % twoPi;
  if (rel <= a1 - a0) return Math.abs(Math.hypot(x - cx, y - cy) - r) - t;
  const e0 = [cx + r * Math.cos(a0), cy + r * Math.sin(a0)];
  const e1 = [cx + r * Math.cos(a1), cy + r * Math.sin(a1)];
  return Math.min(Math.hypot(x - e0[0], y - e0[1]), Math.hypot(x - e1[0], y - e1[1])) - t;
};

/** Union of shapes. @param {...Sdf} fs */
const union = (...fs) => (x, y) => {
  let d = Infinity;
  for (const f of fs) d = Math.min(d, f(x, y));
  return d;
};

/** Rotate a shape by angle a around the local origin. */
const rot = (f, a) => {
  const c = Math.cos(-a), s = Math.sin(-a);
  return (x, y) => f(x * c - y * s, x * s + y * c);
};

/** Translate a shape by (dx, dy). */
const at = (f, dx, dy) => (x, y) => f(x - dx, y - dy);

// ---------------------------------------------------------------------------
// Wrapped two-tone canvas (the seamlessness core)
// ---------------------------------------------------------------------------

/**
 * @typedef {{ covA: Float32Array, covB: Float32Array }} Canvas
 * Two coverage channels (ink tone A / ink tone B) over the background.
 */

/** @returns {Canvas} */
function makeCanvas() {
  return { covA: new Float32Array(TILE * TILE), covB: new Float32Array(TILE * TILE) };
}

/**
 * Paint an SDF into a coverage channel with 1-px anti-aliasing. The write
 * index wraps modulo TILE on both axes, so any shape crossing a tile edge
 * re-enters on the opposite side — seamlessness is arithmetic, not luck.
 * @param {Canvas} cv
 * @param {0|1} tone 0 = ink A, 1 = ink B
 * @param {[number, number, number, number]} bbox [x0, y0, x1, y1] world px
 * @param {Sdf} sdf world-space distance fn
 * @param {number} [alpha] max coverage 0–1
 */
function stampWorld(cv, tone, bbox, sdf, alpha = 1) {
  const buf = tone === 0 ? cv.covA : cv.covB;
  const x0 = Math.floor(bbox[0]);
  const y0 = Math.floor(bbox[1]);
  const x1 = Math.ceil(bbox[2]);
  const y1 = Math.ceil(bbox[3]);
  for (let y = y0; y <= y1; y++) {
    const wy = ((y % TILE) + TILE) % TILE;
    for (let x = x0; x <= x1; x++) {
      const cov = Math.min(1, Math.max(0, 0.5 - sdf(x + 0.5, y + 0.5))) * alpha;
      if (cov <= 0) continue;
      const wx = ((x % TILE) + TILE) % TILE;
      const i = wy * TILE + wx;
      if (cov > buf[i]) buf[i] = cov;
    }
  }
}

/**
 * Stamp one motif instance: the motif paints in LOCAL coordinates through the
 * `m.A(sdf, rad, alpha?)` / `m.B(...)` helpers; this wrapper applies the
 * translate/rotate/scale transform and forwards to the wrapped stamper.
 * @param {Canvas} cv
 * @param {(m: {A: Function, B: Function, rng: () => number}) => void} motif
 * @param {number} cx @param {number} cy world center
 * @param {number} s uniform scale
 * @param {number} a rotation (radians)
 * @param {() => number} rng per-instance random stream
 */
function stampMotif(cv, motif, cx, cy, s, a, rng) {
  const c = Math.cos(-a), sn = Math.sin(-a);
  const paintTone = (tone) => (sdf, rad, alpha = 1) => {
    const R = rad * s + 2;
    const world = (x, y) => {
      const dx = (x - cx) / s, dy = (y - cy) / s;
      return sdf(dx * c - dy * sn, dx * sn + dy * c) * s;
    };
    stampWorld(cv, tone, [cx - R, cy - R, cx + R, cy + R], world, alpha);
  };
  motif({ A: paintTone(0), B: paintTone(1), rng });
}

/** mulberry32 — tiny deterministic PRNG. @param {number} seed */
function mulberry32(seed) {
  let t = seed >>> 0;
  return () => {
    t = (t + 0x6d2b79f5) >>> 0;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

/** FNV-1a string hash (theme name → rng seed). @param {string} str */
function hash(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

// ---------------------------------------------------------------------------
// Theme table — palettes mirror the .screen-<id> blocks in
// src/ui/styles.css (V6/A2 THEMES). bg MUST equal the theme's --thm-bg so
// the baked tile melts into the wash; inkA rides the accent hue, inkB a
// supporting hue. deltaA/deltaB are luma offsets in 0–255 units (≤15.3).
// ---------------------------------------------------------------------------

/**
 * @typedef {Object} Theme
 * @property {string} name pattern file suffix
 * @property {string} bg tile background (equals --thm-bg)
 * @property {string} hueA primary ink hue (mixed toward bg)
 * @property {string} hueB secondary ink hue (mixed toward bg)
 * @property {number} [deltaA] luma offset for ink A (default 13)
 * @property {number} [deltaB] luma offset for ink B (default 10)
 * @property {number} [cells] jittered placement grid (cells × cells)
 * @property {Array<Function>} motifs local-space motif painters
 * @property {(cv: Canvas, rng: () => number, off: [number, number]) => void} [underlay]
 */

// --- shared motif shapes -----------------------------------------------

/** IKEA flat-pack box: outline + tape line + side flap notch. */
const moBox = (m) => {
  m.A(rrRing(0, 0, 15, 12, 3, 1.6), 18);
  m.B(capsule(0, -12, 0, 12, 1.5), 15);
};

/** Allen key (hex key L-shape). */
const moAllenKey = (m) => {
  m.A(union(capsule(-7, 11, -7, -7, 2.8), capsule(-7, -7, 9, -7, 2.8)), 16);
};

/** Row of three shelf-peg dots. */
const moPegs = (m) => {
  m.B(union(circle(-9, 0, 2.6), circle(0, 0, 2.6), circle(9, 0, 2.6)), 13);
};

/** Clothes hanger: hook + shoulder triangle + bar. */
const moHanger = (m) => {
  m.A(arc(0, -12, 4.5, -Math.PI * 0.95, Math.PI * 0.35, 1.6), 20);
  m.A(union(
    capsule(-14, 7, 0, -5, 1.8),
    capsule(14, 7, 0, -5, 1.8),
    capsule(-14, 7, 14, 7, 1.8)
  ), 18);
};

/** Sewing button: rim + two thread holes. */
const moButton = (m) => {
  m.B(ring(0, 0, 8.5, 2), 12);
  m.B(union(circle(-3, 0, 1.7), circle(3, 0, 1.7)), 6);
};

/** Little bow: two triangle loops + knot. */
const moBow = (m) => {
  m.A(union(
    poly([[-12, -6], [-2.5, 0], [-12, 6]]),
    poly([[12, -6], [2.5, 0], [12, 6]]),
    circle(0, 0, 3)
  ), 14);
};

/** Five-point star. */
const moStar = (m) => {
  m.A(star(5, 10.5, 4.6), 12);
};

/** Small four-point sparkle. */
const moSparkle = (m) => {
  m.B(poly([[0, -9], [2, -2], [9, 0], [2, 2], [0, 9], [-2, 2], [-9, 0], [-2, -2]]), 11);
};

/** Arcade joystick: rounded base + stick + ball top. */
const moJoystick = (m) => {
  m.A(roundRect(0, 9, 9.5, 3.6, 3), 14);
  m.A(capsule(0, 7, 0, -5, 2), 10);
  m.B(circle(0, -8, 4.6), 6);
};

/** Corkboard pushpin: round head + needle. */
const moPushpin = (m) => {
  m.A(circle(0, -4.5, 6), 8);
  m.A(capsule(0, 1, 0, 10, 1.3), 12);
};

/** Pinned note scrap with a check mark. */
const moNote = (m) => {
  m.A(rrRing(0, 0, 12, 9.5, 2, 1.5), 15);
  m.B(union(capsule(-4.5, 0.5, -1.5, 3.5, 1.4), capsule(-1.5, 3.5, 5, -3.5, 1.4)), 9);
};

/** Washi-tape strip (rotation supplied by placement). */
const moWashi = (m) => {
  m.A(roundRect(0, 0, 15, 5, 1.5), 17);
};

/** Photo corner: L bracket. */
const moPhotoCorner = (m) => {
  m.B(union(capsule(-9, -9, 9, -9, 1.8), capsule(-9, -9, -9, 9, 1.8)), 12);
};

/** Doodled mini star. */
const moDoodleStar = (m) => {
  m.B(star(5, 7, 3.1), 8);
};

/** Passport entry stamp: rounded frame + inner circle seal. */
const moStamp = (m) => {
  m.A(rrRing(0, 0, 13, 9.5, 3, 1.6), 15);
  m.A(ring(0, 0, 4, 1.4), 6);
};

/** Tiny paper plane. */
const moPlane = (m) => {
  m.B(union(
    poly([[-11, -2], [11, 0], [-6, 4]]),
    poly([[-11, -2], [1, 1], [-4, -9]])
  ), 13);
};

/** Dotted flight arc. */
const moFlightArc = (m) => {
  const dots = [];
  for (let k = 0; k < 5; k++) {
    const a = -Math.PI * 0.8 + k * (Math.PI * 0.6) / 4;
    dots.push(circle(14 * Math.cos(a), 10 + 14 * Math.sin(a), 1.7));
  }
  m.A(union(...dots), 17);
};

/** Clinic plus-cross. */
const moCross = (m) => {
  m.A(union(roundRect(0, 0, 10.5, 3.8, 3), roundRect(0, 0, 3.8, 10.5, 3)), 12);
};

/** Chubby heart. */
const moHeart = (m) => {
  m.B(union(
    circle(-3.6, -2.6, 4.4),
    circle(3.6, -2.6, 4.4),
    poly([[-7.4, -0.9], [7.4, -0.9], [0, 8.2]])
  ), 10);
};

/** Sprouting leaf on a stem. */
const moLeaf = (m) => {
  m.A(rot(ellipse(0, -4, 4.2, 8.5), 0.5), 12);
  m.A(capsule(2, 3, 5, 9, 1.2), 11);
};

/** Eighth note (head + stem + flag). */
const moNote8 = (m) => {
  m.A(rot(ellipse(-3, 8, 4.4, 3.4), -0.35), 10);
  m.A(capsule(0.8, 7, 0.8, -8, 1.4), 11);
  m.A(capsule(0.8, -8, 6.5, -3.5, 1.7), 9);
};

/** Beamed double note. */
const moNote16 = (m) => {
  m.B(rot(ellipse(-8, 8, 3.9, 3), -0.35), 6);
  m.B(rot(ellipse(4, 6.5, 3.9, 3), -0.35), 6);
  m.B(union(capsule(-4.7, 7, -4.7, -7, 1.3), capsule(7.3, 5.5, 7.3, -8.5, 1.3)), 11);
  m.B(poly([[-6, -8.5], [8.6, -10], [8.6, -5.5], [-6, -4]]), 11);
};

/** Radio sound waves. */
const moWaves = (m) => {
  m.A(union(
    arc(-4, 0, 5.5, -Math.PI * 0.35, Math.PI * 0.35, 1.5),
    arc(-4, 0, 10.5, -Math.PI * 0.3, Math.PI * 0.3, 1.5)
  ), 14);
};

/** Laurel sprig: stem arc + leaves fanned along it. */
const moLaurel = (m) => {
  m.B(arc(6, 0, 14, Math.PI * 0.6, Math.PI * 1.35, 1.2), 17);
  for (let k = 0; k < 4; k++) {
    const a = Math.PI * 0.65 + k * (Math.PI * 0.62) / 3;
    const lx = 6 + 14 * Math.cos(a);
    const ly = 14 * Math.sin(a);
    m.B(at(rot(ellipse(0, 0, 4.6, 2), a + 0.9), lx, ly), 17);
  }
};

/** Prize medal: disc + ribbon tails. */
const moMedal = (m) => {
  m.A(ring(0, 3, 6.5, 2), 9);
  m.A(poly([[-4.5, -10], [-0.5, -10], [-1.5, -3.5], [-4.5, -4.5]]), 12);
  m.A(poly([[0.5, -10], [4.5, -10], [4.5, -4.5], [1.5, -3.5]]), 12);
};

/** Blueprint armchair outline. */
const moChair = (m) => {
  m.A(rrRing(0, 5, 9.5, 6, 2.5, 1.3), 13);
  m.A(rrRing(0, -6.5, 7, 4.5, 2, 1.3), 12);
};

/** Blueprint table outline: top + legs. */
const moTable = (m) => {
  m.A(rrRing(0, -4, 13.5, 2.8, 1.5, 1.3), 16);
  m.A(union(capsule(-10.5, -1, -10.5, 9, 1.2), capsule(10.5, -1, 10.5, 9, 1.2)), 13);
};

/** Blueprint floor lamp outline. */
const moLamp = (m) => {
  m.A(poly([[-6.5, -4], [6.5, -4], [4, -12], [-4, -12]]), 14);
  m.A(capsule(0, -4, 0, 9, 1.2), 11);
  m.A(capsule(-5, 9, 5, 9, 1.2), 7);
};

/** @type {readonly Theme[]} */
export const THEMES = Object.freeze([
  {
    name: 'shop', // IKEA-cozy store: cornflower on pale Scandinavian blue
    bg: '#eef4fb', hueA: '#6f9bd6', hueB: '#e8b23f',
    motifs: [moBox, moAllenKey, moPegs],
  },
  {
    name: 'wardrobe', // boutique: hangers/buttons/bows on rose cream
    bg: '#fdf0f4', hueA: '#e78fb3', hueB: '#d6a35f',
    motifs: [moHanger, moButton, moBow],
  },
  {
    name: 'arcade', // arcade hall at dusk: stars/joysticks on lavender
    bg: '#f3effa', hueA: '#9b7fd6', hueB: '#e78fb3',
    motifs: [moStar, moJoystick, moSparkle],
  },
  {
    name: 'quest', // village corkboard: pushpins/notes + cork flecks
    bg: '#f8efe2', hueA: '#c98d5f', hueB: '#a97144',
    motifs: [moPushpin, moNote],
    underlay: (cv, rng, off) => {
      for (let k = 0; k < 110; k++) {
        const x = rng() * TILE + off[0];
        const y = rng() * TILE + off[1];
        const r = 1 + rng() * 1.4;
        stampWorld(cv, 1, [x - r - 1, y - r - 1, x + r + 1, y + r + 1], circle(x, y, r), 0.66);
      }
    },
  },
  {
    name: 'album', // scrapbook: washi strips + photo corners on kraft
    bg: '#f9f3e7', hueA: '#d6a35f', hueB: '#c98d78',
    motifs: [moWashi, moPhotoCorner, moDoodleStar],
  },
  {
    name: 'passport', // travel office: stamps/planes/flight arcs on mint-teal
    bg: '#eff6f4', hueA: '#4fa8a0', hueB: '#6f9bd6',
    motifs: [moStamp, moPlane, moFlightArc],
  },
  {
    name: 'clinic', // pastel clinic: crosses/hearts/leaves on mint
    bg: '#effaf5', hueA: '#59c9b9', hueB: '#e78fb3',
    motifs: [moCross, moHeart, moLeaf],
  },
  {
    name: 'radio', // golden-hour kitchen radio: notes/waves on amber
    bg: '#fdf3e3', hueA: '#e8a13f', hueB: '#a9805a',
    motifs: [moNote8, moWaves, moNote16],
  },
  {
    name: 'trophy', // trophy room: laurels/stars/medals on gold-cream
    bg: '#fbf4e4', hueA: '#e0b04a', hueB: '#9bb56c',
    motifs: [moStar, moLaurel, moMedal],
  },
  {
    name: 'credits', // theatre at dusk: sparkles/hearts on warm grey-cream
    bg: '#f5f0ec', hueA: '#e78fb3', hueB: '#d6a35f',
    motifs: [moSparkle, moHeart, moDoodleStar],
  },
  {
    name: 'blueprint', // decor/furniture-mode: graph grid + furniture outlines
    bg: '#f0f4f7', hueA: '#7fa3b8', hueB: '#7fa3b8',
    deltaB: 5,
    cells: 3,
    motifs: [moChair, moTable, moLamp],
    underlay: (cv, _rng, off) => {
      // graph-paper grid: pitch 64 divides the tile exactly → seamless
      for (let k = 0; k < TILE / 64; k++) {
        const gy = k * 64 + 32 + off[1];
        const gx = k * 64 + 32 + off[0];
        stampWorld(cv, 1, [off[0] - 1, gy - 2, off[0] + TILE + 1, gy + 2],
          (x, y) => Math.abs(y - gy) - 0.8);
        stampWorld(cv, 1, [gx - 2, off[1] - 1, gx + 2, off[1] + TILE + 1],
          (x) => Math.abs(x - gx) - 0.8);
      }
    },
  },
]);

// ---------------------------------------------------------------------------
// Renderer: jittered-grid placement → quantized indexed image
// ---------------------------------------------------------------------------

/** Quantized coverage levels (4 per tone → ≤16 palette entries). */
const LEVELS = [0, 1 / 3, 2 / 3, 1];

/**
 * Render one theme into palette indices. `off` shifts every placement by a
 * constant vector — used by the seam self-check (content offset by (dx, dy)
 * must equal the torus-rolled base render).
 * @param {Theme} theme
 * @param {[number, number]} [off]
 * @returns {{indices: Uint8Array, palette: Array<[number, number, number]>}}
 */
export function renderTheme(theme, off = [0, 0]) {
  const cv = makeCanvas();
  const rng = mulberry32(hash(theme.name));
  if (theme.underlay) theme.underlay(cv, rng, off);
  const cells = theme.cells ?? 4;
  const cell = TILE / cells;
  let k = 0;
  for (let r = 0; r < cells; r++) {
    for (let c = 0; c < cells; c++) {
      const motif = theme.motifs[k % theme.motifs.length];
      k++;
      const jx = (rng() - 0.5) * cell * 0.5;
      const jy = (rng() - 0.5) * cell * 0.5;
      // half-cell offset on odd rows → the ACNH diagonal rhythm
      const cx = (c + 0.5 + (r % 2 ? 0.5 : 0)) * cell + jx + off[0];
      const cy = (r + 0.5) * cell + jy + off[1];
      const s = (cell / 128) * (1.15 + rng() * 0.5);
      const a = (rng() - 0.5) * 0.7;
      stampMotif(cv, motif, cx, cy, s, a, rng);
    }
  }

  // quantize the two coverage channels → 16-entry palette
  const bg = rgb(theme.bg);
  const inkA = toneFor(bg, rgb(theme.hueA), theme.deltaA ?? 13);
  const inkB = toneFor(bg, rgb(theme.hueB), theme.deltaB ?? 10);
  const palette = [];
  for (let qa = 0; qa < 4; qa++) {
    for (let qb = 0; qb < 4; qb++) {
      const withA = mix(bg, inkA, LEVELS[qa]);
      palette.push(mix(withA, inkB, LEVELS[qb]));
    }
  }
  const indices = new Uint8Array(TILE * TILE);
  for (let i = 0; i < indices.length; i++) {
    const qa = Math.round(cv.covA[i] * 3);
    const qb = Math.round(cv.covB[i] * 3);
    indices[i] = qa * 4 + qb;
  }
  return { indices, palette };
}

/**
 * Seam self-check: rendering with every placement shifted by `off` must equal
 * the base render rolled by `off` on the torus. Any stamp that clipped at a
 * tile edge instead of wrapping breaks this equality.
 * @param {Theme} theme
 * @param {Uint8Array} base base-render indices
 */
function verifySeamless(theme, base) {
  const [ox, oy] = [137, 289];
  const shifted = renderTheme(theme, [ox, oy]).indices;
  for (let y = 0; y < TILE; y++) {
    for (let x = 0; x < TILE; x++) {
      const sx = (x + ox) % TILE;
      const sy = (y + oy) % TILE;
      if (shifted[sy * TILE + sx] !== base[y * TILE + x]) {
        throw new Error(`gen-patterns: ${theme.name} is NOT seamless (mismatch at ${x},${y})`);
      }
    }
  }
}

/**
 * Contrast self-check: every palette entry within MAX_LUMA_DELTA of entry 0.
 * @param {Theme} theme
 * @param {Array<[number, number, number]>} palette
 */
function verifyContrast(theme, palette) {
  const base = luma(palette[0]);
  for (const c of palette) {
    const d = Math.abs(luma(c) - base);
    if (d > MAX_LUMA_DELTA) {
      throw new Error(`gen-patterns: ${theme.name} palette delta ${d.toFixed(1)} > ${MAX_LUMA_DELTA.toFixed(1)}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const outDir = join(root, 'public/assets/acui');
  mkdirSync(outDir, { recursive: true });
  let total = 0;
  for (const theme of THEMES) {
    const { indices, palette } = renderTheme(theme);
    verifySeamless(theme, indices);
    verifyContrast(theme, palette);
    const png = encodeIndexedPng(TILE, indices, palette);
    if (png.length > MAX_TILE_BYTES) {
      throw new Error(`gen-patterns: pattern_${theme.name}.png is ${png.length} B > ${MAX_TILE_BYTES} B`);
    }
    total += png.length;
    writeFileSync(join(outDir, `pattern_${theme.name}.png`), png);
    console.log(`pattern_${theme.name}.png  ${TILE}×${TILE}  ${png.length.toLocaleString()} B  (seamless ✓, ≤6 % contrast ✓)`);
  }
  if (total > MAX_AGGREGATE_BYTES) {
    throw new Error(`gen-patterns: aggregate ${total} B > ${MAX_AGGREGATE_BYTES} B`);
  }
  console.log(`aggregate ${total.toLocaleString()} B ≤ ${MAX_AGGREGATE_BYTES.toLocaleString()} B ✓`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main();
}
