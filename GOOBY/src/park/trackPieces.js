// V6/E2 — Funkelpark coaster track-piece catalog + socket math (PLAN6 Wave
// E/E2). PURE: no three/DOM imports — node:test drives it headlessly
// (test/coasterRide.test.js) and the view (park/coasterRide.js) renders the
// assembled track 1:1. The socket model is extracted from
// minigames/games/toyRacer.logic.js (the idea doc's binding precedent): grid
// walk with 4 headings, all turns are LEFT 90° (the committed toy-car-kit
// corner GLBs are left-handed — no mirrored models exist), pieces travel +z
// in their local frame.
//
// Piece dimensions are MEASURED, never eyeballed (PLAN6 E2 acceptance): the
// toy-car-kit GLBs are not in test/fixtures/asset-bounds.json, so they were
// audited headlessly with the gen-asset-bounds approach (raw GLB parse:
// composed node transforms × accessor POSITION min/max). Audit table (track
// units — 1 unit = 1 GLB unit = the narrow track's width):
//
//   track-narrow-straight            size 1.0 × 0.3 × 4.4   road at y −0.7
//   track-narrow-straight-bump-up    size 1.0 × 0.8 × 4.4   road −0.7 → −0.2
//   track-narrow-straight-bump-down  size 1.0 × 0.8 × 4.4   road −0.7 → −1.2
//   track-narrow-corner-small        size 2.7 × 0.3 × 2.7   (r = 2 left arc)
//   track-narrow-corner-large        size 4.7 × 0.3 × 4.7   (r = 4 left arc)
//   track-narrow-curve               size 3.0 × 0.3 × 4.4   (lane shift 2 left)
//   track-narrow-looping             size 2.0 × 4.0 × 3.98  origin at piece
//     CENTER (originOffset 2), inner riding circle r ≈ 1.7, apex road y +2.7,
//     exit shifted 1 unit left (corkscrew drift)
//   supports.glb                     1 × 1 × 1 column block
//   supports-clamp.glb               1.2 × 0.35 × 1 top clamp
//
// Every GLB's z span is −0.2…len+0.2 (0.2 connector lips overhang each
// socket) and the RIDING SURFACE sits 0.7 units BELOW the GLB origin —
// ROAD_Y_OFFSET below mirrors toyRacer.js's placement (origin y = track y +
// 0.7). §E0.1-2: all exact numbers are frozen consts inside this module.

/** GLB-origin height above the riding surface (bbox audit: road at y −0.7). */
export const ROAD_Y_OFFSET = 0.7;

/** Narrow-track width (units) — cart/camera lateral bounds. */
export const TRACK_WIDTH = 1;

/**
 * The measured piece catalog. `len`/`r`/`shift`/`dy` are riding-surface
 * geometry in track units; `model` is the committed toy-car-kit GLB key
 * suffix; `originOffset` = distance from the GLB origin to the ENTRY socket
 * along the travel axis (only the loop GLB is center-origined).
 */
export const TRACK_PIECES = Object.freeze({
  straight: Object.freeze({ kind: 'straight', len: 4, dy: 0, model: 'track-narrow-straight' }),
  bumpUp: Object.freeze({ kind: 'straight', len: 4, dy: 0.5, model: 'track-narrow-straight-bump-up' }),
  bumpDown: Object.freeze({ kind: 'straight', len: 4, dy: -0.5, model: 'track-narrow-straight-bump-down' }),
  cornerS: Object.freeze({ kind: 'corner', r: 2, model: 'track-narrow-corner-small' }),
  cornerL: Object.freeze({ kind: 'corner', r: 4, model: 'track-narrow-corner-large' }),
  curve: Object.freeze({ kind: 'shift', len: 4, shift: 2, model: 'track-narrow-curve' }),
  loop: Object.freeze({
    kind: 'loop', len: 4, shift: 1, r: 1.7, entry: 2, model: 'track-narrow-looping', originOffset: 2,
  }),
});

/** Support prop models + placement tuning (measured above). */
export const SUPPORTS = Object.freeze({
  column: 'supports',
  clamp: 'supports-clamp',
  /** Track height (units) below which no column is placed. */
  MIN_Y: 0.3,
  /** Arc-length spacing (units) between column probes. */
  SPACING: 2.5,
});

/** Grid heading vectors (x, z): 0=+z · 1=−x · 2=−z · 3=+x (toyRacer model). */
export const DIRS = Object.freeze([
  Object.freeze([0, 1]),
  Object.freeze([-1, 0]),
  Object.freeze([0, -1]),
  Object.freeze([1, 0]),
]);

/** dir index → model rotY (GLBs travel +z in their local frame). */
export const DIR_ROT_Y = Object.freeze([0, -Math.PI / 2, Math.PI, Math.PI / 2]);

/** @param {number} d @returns {number} left-turned heading index */
export function leftOf(d) {
  return (d + 1) % 4;
}

/** All model keys the coaster view must preload (track + supports). */
export const PIECE_MODEL_KEYS = Object.freeze([
  ...new Set(Object.values(TRACK_PIECES).map((def) => `toy-car-kit/${def.model}`)),
  `toy-car-kit/${SUPPORTS.column}`,
  `toy-car-kit/${SUPPORTS.clamp}`,
]);

/**
 * Local socket transform of one piece type. The ENTRY socket is always the
 * local origin facing +z; the EXIT socket is expressed in the entry frame as
 * forward/left/up displacements + a turn count (left 90° units) — this is
 * the independent "truth table" the 1 mm socket-join test checks the emitted
 * center-line against.
 * @param {string} type TRACK_PIECES key
 * @returns {{fwd: number, left: number, up: number, turn: number}}
 */
export function localSockets(type) {
  const def = TRACK_PIECES[type];
  if (!def) throw new Error(`trackPieces: unknown piece type '${type}'`);
  switch (def.kind) {
    case 'straight':
      return { fwd: def.len, left: 0, up: def.dy, turn: 0 };
    case 'corner':
      return { fwd: def.r, left: def.r, up: 0, turn: 1 };
    case 'shift':
      return { fwd: def.len, left: def.shift, up: 0, turn: 0 };
    default: // loop
      return { fwd: def.len, left: def.shift, up: 0, turn: 0 };
  }
}

const smooth = (t) => t * t * (3 - 2 * t);
const vlen = (v) => Math.hypot(v[0], v[1], v[2]);
const norm = (v) => {
  const n = vlen(v) || 1;
  return [v[0] / n, v[1] / n, v[2] / n];
};

/** Fine parametric step (units along the dominant axis — toyRacer's 0.06). */
const FINE = 0.06;

/**
 * Emit fine center-line points (+ up vectors through the vertical loop) for
 * one piece — the parametrizations mirror toyRacer.logic.js emitPiece
 * exactly (straight smoothstep bumps · quarter-circle corners · smoothstep
 * lane shift · entry/2π-circle-with-corkscrew-drift/exit loop).
 * @param {object} def TRACK_PIECES entry
 * @param {{x: number, y: number, z: number, dir: number}} cur entry pose
 * @returns {Array<{p: number[], up: number[]}>}
 */
function emitPiece(def, cur) {
  const h = DIRS[cur.dir];
  const l = DIRS[leftOf(cur.dir)];
  const points = [];
  if (def.kind === 'straight') {
    const n = Math.ceil(def.len / FINE);
    for (let i = 0; i < n; i += 1) {
      const u = (i / n) * def.len;
      const t = u / def.len;
      points.push({
        p: [cur.x + h[0] * u, cur.y + def.dy * smooth(t), cur.z + h[1] * u],
        up: [0, 1, 0],
      });
    }
    return points;
  }
  if (def.kind === 'corner') {
    const r = def.r;
    const cx = cur.x + l[0] * r;
    const cz = cur.z + l[1] * r;
    const n = Math.ceil(((Math.PI / 2) * r) / FINE);
    for (let i = 0; i < n; i += 1) {
      const phi = (i / n) * (Math.PI / 2);
      points.push({
        p: [
          cx - l[0] * r * Math.cos(phi) + h[0] * r * Math.sin(phi),
          cur.y,
          cz - l[1] * r * Math.cos(phi) + h[1] * r * Math.sin(phi),
        ],
        up: [0, 1, 0],
      });
    }
    return points;
  }
  if (def.kind === 'shift') {
    const n = Math.ceil(def.len / FINE);
    for (let i = 0; i < n; i += 1) {
      const u = (i / n) * def.len;
      const t = u / def.len;
      points.push({
        p: [cur.x + h[0] * u + l[0] * def.shift * smooth(t), cur.y, cur.z + h[1] * u + l[1] * def.shift * smooth(t)],
        up: [0, 1, 0],
      });
    }
    return points;
  }
  // vertical loop: entry straight → 2π circle in the (heading, y) plane with
  // a `shift`-unit corkscrew drift to the left → exit straight.
  const R = def.r;
  const entry = def.entry ?? def.len / 2;
  const exit = def.len - entry;
  const nE = Math.ceil(entry / FINE);
  for (let i = 0; i < nE; i += 1) {
    const u = (i / nE) * entry;
    points.push({ p: [cur.x + h[0] * u, cur.y, cur.z + h[1] * u], up: [0, 1, 0] });
  }
  const c0x = cur.x + h[0] * entry;
  const c0z = cur.z + h[1] * entry;
  const nC = Math.ceil((2 * Math.PI * R) / FINE);
  for (let i = 0; i < nC; i += 1) {
    const th = (i / nC) * Math.PI * 2;
    const drift = (th / (Math.PI * 2)) * def.shift;
    points.push({
      p: [
        c0x + h[0] * R * Math.sin(th) + l[0] * drift,
        cur.y + R * (1 - Math.cos(th)),
        c0z + h[1] * R * Math.sin(th) + l[1] * drift,
      ],
      // up points from the cart toward the loop center (same lateral slice)
      up: [-h[0] * Math.sin(th), Math.cos(th), -h[1] * Math.sin(th)],
    });
  }
  const exX = c0x + l[0] * def.shift;
  const exZ = c0z + l[1] * def.shift;
  const nX = Math.ceil(exit / FINE);
  for (let i = 0; i < nX; i += 1) {
    const u = (i / nX) * exit;
    points.push({ p: [exX + h[0] * u, cur.y, exZ + h[1] * u], up: [0, 1, 0] });
  }
  return points;
}

/** Uniform arc-length resample step (track units). */
export const SAMPLE_STEP = 0.25;

/**
 * Assemble a closed circuit from a piece-type layout: per-piece world
 * transforms (for the view's InstancedMesh placement), independent
 * entry/exit socket poses (for the ≤1 mm join test), and a continuous
 * arc-length-parametrized center-line spline with per-sample tangents/ups.
 *
 * @param {string[]} layout TRACK_PIECES keys, walked from (0,0,0) facing +z
 * @returns {{
 *   pieces: Array<{index: number, type: string, model: string,
 *     x: number, y: number, z: number, dir: number, rotY: number,
 *     originOffset: number, entry: number[], exit: number[],
 *     entryDir: number, exitDir: number, s0: number, s1: number}>,
 *   samples: Array<{p: number[], up: number[], t: number[]}>,
 *   step: number, totalLen: number, closed: boolean, closeError: number,
 * }}
 */
export function assembleTrack(layout) {
  if (!Array.isArray(layout) || layout.length === 0) {
    throw new Error('trackPieces: assembleTrack needs a non-empty layout');
  }
  let cur = { x: 0, y: 0, z: 0, dir: 0 };
  const pieces = [];
  const fine = [];
  const pieceFineFrom = [];
  for (let i = 0; i < layout.length; i += 1) {
    const type = layout[i];
    const def = TRACK_PIECES[type];
    const sock = localSockets(type);
    const h = DIRS[cur.dir];
    const l = DIRS[leftOf(cur.dir)];
    const exit = [
      cur.x + h[0] * sock.fwd + l[0] * sock.left,
      cur.y + sock.up,
      cur.z + h[1] * sock.fwd + l[1] * sock.left,
    ];
    pieces.push({
      index: i,
      type,
      model: def.model,
      x: cur.x,
      y: cur.y,
      z: cur.z,
      dir: cur.dir,
      rotY: DIR_ROT_Y[cur.dir],
      originOffset: def.originOffset ?? 0,
      entry: [cur.x, cur.y, cur.z],
      exit,
      entryDir: cur.dir,
      exitDir: (cur.dir + sock.turn) % 4,
      s0: 0, // filled below from the fine arc-length table
      s1: 0,
    });
    pieceFineFrom.push(fine.length);
    fine.push(...emitPiece(def, cur));
    cur = { x: exit[0], y: exit[1], z: exit[2], dir: (cur.dir + sock.turn) % 4 };
  }
  pieceFineFrom.push(fine.length);

  const closeError = Math.hypot(cur.x, cur.y, cur.z);
  const closed = closeError < 1e-9 && cur.dir === 0;

  // uniform arc-length resample over the closed loop (toyRacer's algorithm)
  const step = SAMPLE_STEP;
  const samples = [];
  let acc = 0;
  let prev = fine[0];
  samples.push({ p: [...prev.p], up: [...prev.up] });
  const fineS = [0];
  for (let i = 1; i <= fine.length; i += 1) {
    const pt = fine[i % fine.length];
    const d = Math.hypot(pt.p[0] - prev.p[0], pt.p[1] - prev.p[1], pt.p[2] - prev.p[2]);
    const segStart = acc;
    acc += d;
    fineS.push(acc);
    while (samples.length * step <= acc && d > 0) {
      const target = samples.length * step;
      const f = (target - segStart) / d;
      samples.push({
        p: [
          prev.p[0] + (pt.p[0] - prev.p[0]) * f,
          prev.p[1] + (pt.p[1] - prev.p[1]) * f,
          prev.p[2] + (pt.p[2] - prev.p[2]) * f,
        ],
        up: norm([
          prev.up[0] + (pt.up[0] - prev.up[0]) * f,
          prev.up[1] + (pt.up[1] - prev.up[1]) * f,
          prev.up[2] + (pt.up[2] - prev.up[2]) * f,
        ]),
      });
    }
    prev = pt;
  }
  const totalLen = acc;

  // per-piece arc-length ranges (the ride logic's zone/cue source of truth)
  for (let i = 0; i < pieces.length; i += 1) {
    pieces[i].s0 = fineS[pieceFineFrom[i]];
    pieces[i].s1 = i + 1 < pieces.length ? fineS[pieceFineFrom[i + 1]] : totalLen;
  }

  // tangents: central difference over the closed loop
  const n = samples.length;
  for (let i = 0; i < n; i += 1) {
    const a = samples[(i - 1 + n) % n].p;
    const b = samples[(i + 1) % n].p;
    samples[i].t = norm([b[0] - a[0], b[1] - a[1], b[2] - a[2]]);
  }

  return { pieces, samples, step, totalLen, closed, closeError };
}

/**
 * Sample the center spline at arc distance s (wraps around the circuit).
 * @param {{samples: Array<object>, step: number, totalLen: number}} assembly
 * @param {number} s
 * @returns {{p: number[], t: number[], up: number[]}}
 */
export function pointAt(assembly, s) {
  const n = assembly.samples.length;
  let u = (s % assembly.totalLen) / assembly.step;
  if (u < 0) u += n;
  const i0 = Math.floor(u) % n;
  const i1 = (i0 + 1) % n;
  const f = u - Math.floor(u);
  const a = assembly.samples[i0];
  const b = assembly.samples[i1];
  const lerp3 = (x, y) => [x[0] + (y[0] - x[0]) * f, x[1] + (y[1] - x[1]) * f, x[2] + (y[2] - x[2]) * f];
  return { p: lerp3(a.p, b.p), t: norm(lerp3(a.t, b.t)), up: norm(lerp3(a.up, b.up)) };
}

/**
 * Auto-place support columns under elevated track (PLAN6 E2: "supports
 * auto-placed under elevated track"). Probes the center line every
 * SUPPORTS.SPACING arc units; loop pieces are skipped (their circle rides
 * ABOVE the piece's own base — a column under the circle would pierce it).
 * @param {ReturnType<typeof assembleTrack>} assembly
 * @returns {Array<{p: number[], h: number}>} column foot positions (y = 0)
 *   with column heights (track y of the riding surface at that point)
 */
export function computeSupports(assembly) {
  const out = [];
  const loopSpans = assembly.pieces
    .filter((piece) => piece.type === 'loop')
    .map((piece) => [piece.s0, piece.s1]);
  for (let s = 0; s < assembly.totalLen; s += SUPPORTS.SPACING) {
    if (loopSpans.some(([s0, s1]) => s >= s0 && s <= s1)) continue;
    const smp = pointAt(assembly, s);
    if (smp.p[1] > SUPPORTS.MIN_Y) {
      out.push({ p: [smp.p[0], 0, smp.p[2]], h: smp.p[1] });
    }
  }
  return out;
}
