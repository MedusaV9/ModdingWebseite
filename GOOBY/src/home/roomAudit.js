// V4/AC-3D: headless 3D-placement audit for the home rooms — PURE data math,
// NO three.js/DOM imports (test/roomAudit.test.js runs it under node:test).
//
// The user-facing guarantee this module machine-checks: no placed model may
// clip into another, face the wrong way, stand tilted, float in the air, sink
// into the floor, pierce a wall or hang outside its room shell. The ground
// truth is test/fixtures/asset-bounds.json (scripts/gen-asset-bounds.mjs):
// per-asset NATIVE bounding boxes + canonical forward vectors, plus live
// placed-box dumps that lock this module's transform replay against the real
// roomManager scene graph (drift ≤ 0.05 m).
//
// ── Contract ────────────────────────────────────────────────────────────────
//   computePlacedBoxes(roomDef, assetBounds, opts) -> PlacedBox[]
//     Replays roomManager's furniture transform chain exactly:
//       native box → ×FURNITURE_SCALE → groundAndCenter (footprint centered
//       on x/z, bbox bottom on y=0) → piece scale/rotY/at → entry
//       scale/rotY/at — every corner pushed through the COMPOSED transform
//       (matching three.js matrixWorld math, so the drift check is exact).
//     Procedural builds (`proc:` keys) skip scale+grounding (builders are
//     authored grounded in holder space). With opts.includeDressing (default
//     true) the V4/G79 `asset`/`assetCluster` dressing entries are replayed
//     through decor.js's chain (scale → rotXYZ → groundAndCenter → +at).
//     opts.extras replays pinned cross-file fixtures (the living radio).
//   auditRoom(roomDef, assetBounds, rules, opts) -> Warning[]
//     Warning types: 'clip' | 'wall-penetration' | 'out-of-shell' | 'facing'
//     | 'tilt' | 'float' | 'sunk'. An empty array is the shipping bar —
//     test/roomAudit.test.js locks all 5 rooms to zero warnings.
//
// Shell numbers mirror roomManager.SHELL / rooms/garden.GARDEN_SIZE (kept in
// sync by hand — this module must stay importable without three.js; the
// fixture's meta block carries the same numbers and wins when present).

/**
 * @typedef {{min: number[], max: number[]}} Box3Like
 * @typedef {{
 *   source: 'furniture'|'dressing'|'extra',
 *   index: number|string, key: string, label: string,
 *   slot?: string, interact?: string, anchor?: string, noShadow?: boolean,
 *   min: number[], max: number[],
 *   rotY: number, forward: number[]|null, flat: boolean,
 * }} PlacedBox
 * @typedef {{
 *   type: 'clip'|'wall-penetration'|'out-of-shell'|'facing'|'tilt'|'float'|'sunk',
 *   room: string, a: string, b?: string, amount?: number, msg: string,
 * }} Warning
 */

/** Mirror of roomManager.FURNITURE_SCALE (kept in sync by hand). */
export const FURNITURE_SCALE = 1.55;

/** Mirror of roomManager.SHELL (indoor) / rooms/garden GARDEN_SIZE. */
export const SHELL_DIMS = Object.freeze({
  width: 4, depth: 3, height: 3.2, sideDepth: 1.9, wallThickness: 0.12,
});
export const GARDEN_DIMS = Object.freeze({ width: 5, depth: 4 });

/** Default tolerances — rules.global overrides individual values. */
export const DEFAULT_TOLERANCES = Object.freeze({
  /** AABB interpenetration beyond this is a clip (flush fits stay legal). */
  clipTol: 0.035,
  /** how deep a non-wall-mounted box may cross a wall's inner face */
  wallTol: 0.02,
  /** wall-mounted pieces may embed up to the wall thickness, never beyond */
  wallEmbedMax: 0.12,
  /** upper.min.y >= lower.max.y - stackGap ⇒ deliberate y-stack, not a clip */
  stackGap: 0.05,
  /** boxes at most this tall are 'flat' (rugs/paths) — may lie under anything */
  flatMax: 0.09,
  /** floor items whose bottom is above this must be supported or mounted */
  floatMax: 0.08,
  /** bottoms below this are sunk into the floor */
  sunkMin: -0.05,
  /** a supporter's top may be at most this far below a resting bottom */
  supportTol: 0.07,
  /** wall-backed furniture must keep its back within this of the wall */
  backMax: 0.15,
  /** slack on the room-shell footprint before 'out-of-shell' */
  edgeTol: 0.05,
  /** facing cones (degrees) */
  cameraMaxDeg: 60,
  targetMaxDeg: 75,
});

const DEG = Math.PI / 180;

/** V2/G19 mirror of roomManager.resolveAssetKey (pure). */
export const resolveAssetKey = (item) =>
  item.includes('/') ? item : `furniture-kit/${item}`;

// ---------------------------------------------------------------------------
// vec3 / AABB helpers (inline — no three.js)
// ---------------------------------------------------------------------------

const newBox = () => ({
  min: [Infinity, Infinity, Infinity],
  max: [-Infinity, -Infinity, -Infinity],
});

function growPoint(box, p) {
  for (let i = 0; i < 3; i += 1) {
    if (p[i] < box.min[i]) box.min[i] = p[i];
    if (p[i] > box.max[i]) box.max[i] = p[i];
  }
}

/** The 8 corners of an AABB. @param {Box3Like} b @returns {number[][]} */
function corners(b) {
  const out = [];
  for (const x of [b.min[0], b.max[0]]) {
    for (const y of [b.min[1], b.max[1]]) {
      for (const z of [b.min[2], b.max[2]]) out.push([x, y, z]);
    }
  }
  return out;
}

/** Rotate [x,y,z] about +y by deg (three.js handedness). */
function rotY(p, deg) {
  if (!deg) return p;
  const c = Math.cos(deg * DEG);
  const s = Math.sin(deg * DEG);
  return [c * p[0] + s * p[2], p[1], -s * p[0] + c * p[2]];
}

/** Rotate about +x by deg. */
function rotX(p, deg) {
  if (!deg) return p;
  const c = Math.cos(deg * DEG);
  const s = Math.sin(deg * DEG);
  return [p[0], c * p[1] - s * p[2], s * p[1] + c * p[2]];
}

/** Rotate about +z by deg. */
function rotZ(p, deg) {
  if (!deg) return p;
  const c = Math.cos(deg * DEG);
  const s = Math.sin(deg * DEG);
  return [c * p[0] - s * p[1], s * p[0] + c * p[1], p[2]];
}

/** Per-axis scale (scalar or [sx,sy,sz]). */
function scaleP(p, s) {
  if (s == null || s === 1) return p;
  if (Array.isArray(s)) return [p[0] * s[0], p[1] * s[1], p[2] * s[2]];
  return [p[0] * s, p[1] * s, p[2] * s];
}

const addP = (p, t) => [p[0] + t[0], p[1] + t[1], p[2] + t[2]];

/**
 * groundAndCenter replay (roomManager): recenter footprint on x/z, drop the
 * bbox bottom to y=0.
 * @param {Box3Like} b @returns {Box3Like}
 */
function groundedBox(b) {
  const cx = (b.min[0] + b.max[0]) / 2;
  const cz = (b.min[2] + b.max[2]) / 2;
  return {
    min: [b.min[0] - cx, 0, b.min[2] - cz],
    max: [b.max[0] - cx, b.max[1] - b.min[1], b.max[2] - cz],
  };
}

// ---------------------------------------------------------------------------
// computePlacedBoxes
// ---------------------------------------------------------------------------

/**
 * @param {object} roomDef pure room table (rooms/*.js ROOM)
 * @param {object} assetBounds the asset-bounds fixture root (or a bare
 *   `{ key: {min,max,forward} }` map)
 * @param {{
 *   furnitureScale?: number, includeDressing?: boolean,
 *   extras?: Array<{id: string, key: string, at: number[], rotY?: number, scale?: number}>,
 *   flatMax?: number,
 * }} [opts]
 * @returns {PlacedBox[]}
 */
export function computePlacedBoxes(roomDef, assetBounds, opts = {}) {
  const bounds = assetBounds.assets ?? assetBounds;
  const fScale = opts.furnitureScale ?? assetBounds.meta?.furnitureScale ?? FURNITURE_SCALE;
  const flatMax = opts.flatMax ?? DEFAULT_TOLERANCES.flatMax;
  /** @type {PlacedBox[]} */
  const out = [];

  const push = (source, index, key, entryBits, box, rotYTotal, native) => {
    const forward = native?.forward
      ? (() => {
        const f = rotY(native.forward, rotYTotal);
        return [f[0], f[2]];
      })()
      : null;
    out.push({
      source, index, key,
      label: `${roomDef.id}[${index}] ${key}`,
      slot: entryBits.slot, interact: entryBits.interact,
      anchor: entryBits.anchor, noShadow: entryBits.noShadow,
      min: box.min, max: box.max,
      rotY: rotYTotal, forward,
      flat: box.max[1] - box.min[1] <= flatMax,
    });
  };

  // ── furniture entries (roomManager chain) ────────────────────────────────
  for (let i = 0; i < roomDef.furniture.length; i += 1) {
    const entry = roomDef.furniture[i];
    if (entry.slot && !entry.item && !entry.pieces && !entry.proc) continue; // empty slot

    if (entry.proc) {
      const key = `proc:${entry.proc}`;
      const nb = bounds[key];
      if (!nb) throw new Error(`asset-bounds fixture is missing '${key}'`);
      const box = newBox();
      for (const c of corners(nb)) {
        growPoint(box, addP(rotY(scaleP(c, entry.scale ?? 1), entry.rotY ?? 0), entry.at));
      }
      push('furniture', i, key, entry, box, entry.rotY ?? 0, nb);
      continue;
    }

    const pieces = entry.pieces ?? [{ item: entry.item, at: [0, 0, 0], rotY: 0 }];
    for (const piece of pieces) {
      const key = resolveAssetKey(piece.item);
      const nb = bounds[key];
      if (!nb) throw new Error(`asset-bounds fixture is missing '${key}'`);
      const grounded = groundedBox({
        min: scaleP(nb.min, fScale), max: scaleP(nb.max, fScale),
      });
      const box = newBox();
      for (const c of corners(grounded)) {
        // piece TRS then entry TRS — corners composed through BOTH levels in
        // one pass (matches three.js matrixWorld composition exactly)
        const p1 = addP(rotY(scaleP(c, piece.scale ?? 1), piece.rotY ?? 0), piece.at);
        growPoint(box, addP(rotY(scaleP(p1, entry.scale ?? 1), entry.rotY ?? 0), entry.at));
      }
      push('furniture', i, key, entry, box, (entry.rotY ?? 0) + (piece.rotY ?? 0), nb);
    }
  }

  // ── V4/G79 dressing (decor.js g79AssetGeometries chain) ──────────────────
  if (opts.includeDressing !== false) {
    for (const entry of roomDef.dressing ?? []) {
      if (entry.kind !== 'asset' && entry.kind !== 'assetCluster') continue;
      const pieces = entry.kind === 'assetCluster' ? entry.pieces : [entry];
      for (const piece of pieces) {
        const nb = bounds[piece.key];
        if (!nb) throw new Error(`asset-bounds fixture is missing '${piece.key}'`);
        // decor chain: scale → rotXYZ (three 'XYZ' euler) → groundAndCenter
        // (on the ROTATED box) → translate by at
        const rotated = newBox();
        for (const c of corners(nb)) {
          growPoint(rotated,
            rotX(rotY(rotZ(scaleP(c, piece.scale ?? 1), piece.rotZ ?? 0), piece.rotY ?? 0), piece.rotX ?? 0));
        }
        const g = groundedBox(rotated);
        const box = { min: addP(g.min, piece.at), max: addP(g.max, piece.at) };
        const tilted = (piece.rotX ?? 0) !== 0 || (piece.rotZ ?? 0) !== 0;
        push('dressing', `dressing:${entry.id}`, piece.key,
          { ...entry, rotXZ: tilted }, box, piece.rotY ?? 0,
          tilted ? { ...nb, forward: null } : nb);
        out[out.length - 1].rotXZ = tilted ? [piece.rotX ?? 0, piece.rotZ ?? 0] : null;
      }
    }
  }

  // ── pinned cross-file extras (living radio fixture) ──────────────────────
  for (const extra of opts.extras ?? []) {
    const nb = bounds[extra.key];
    if (!nb) throw new Error(`asset-bounds fixture is missing '${extra.key}'`);
    const g = groundedBox({
      min: scaleP(nb.min, extra.scale ?? 1), max: scaleP(nb.max, extra.scale ?? 1),
    });
    const box = newBox();
    for (const c of corners(g)) growPoint(box, addP(rotY(c, extra.rotY ?? 0), extra.at));
    push('extra', `extra:${extra.id}`, extra.key, extra, box, extra.rotY ?? 0, nb);
  }

  return out;
}

// ---------------------------------------------------------------------------
// auditRoom
// ---------------------------------------------------------------------------

const overlap1D = (a, b, axis) =>
  Math.min(a.max[axis], b.max[axis]) - Math.max(a.min[axis], b.min[axis]);

function pairAllowed(allowList, a, b) {
  for (const [ka, kb] of allowList ?? []) {
    if ((a.key === ka && b.key === kb) || (a.key === kb && b.key === ka)) return true;
  }
  return false;
}

/** b rests on some other box: horizontal overlap + top near/above its bottom. */
function isSupported(b, boxes, tol) {
  for (const o of boxes) {
    if (o === b) continue;
    if (overlap1D(b, o, 0) <= 0.02 || overlap1D(b, o, 2) <= 0.02) continue;
    if (o.min[1] >= b.min[1]) continue; // supporter must start below
    if (o.max[1] + tol < b.min[1]) continue; // top too far below
    // the resting box's footprint CENTER must be over the supporter — a box
    // half-hanging off a shelf edge reads as floating, so it stays a warning
    const cx = (b.min[0] + b.max[0]) / 2;
    const cz = (b.min[2] + b.max[2]) / 2;
    if (cx >= o.min[0] - 0.02 && cx <= o.max[0] + 0.02
      && cz >= o.min[2] - 0.02 && cz <= o.max[2] + 0.02) return true;
  }
  return false;
}

const angleDeg = (a, b) => {
  const la = Math.hypot(a[0], a[1]);
  const lb = Math.hypot(b[0], b[1]);
  if (la === 0 || lb === 0) return 0;
  const cos = Math.min(1, Math.max(-1, (a[0] * b[0] + a[1] * b[1]) / (la * lb)));
  return Math.acos(cos) / DEG;
};

/**
 * @param {object} roomDef
 * @param {object} assetBounds fixture root (or bare bounds map)
 * @param {{global?: object, rooms?: Record<string, object>}} [rules]
 *   per-room rule block: { facing, clipAllow, wallMounted, elevated,
 *   edgeAllow, tiltAllow, extras }
 * @param {object} [opts] forwarded to computePlacedBoxes
 * @returns {Warning[]}
 */
export function auditRoom(roomDef, assetBounds, rules = {}, opts = {}) {
  const tol = { ...DEFAULT_TOLERANCES, ...(rules.global ?? {}) };
  const roomRules = rules.rooms?.[roomDef.id] ?? {};
  const boxes = computePlacedBoxes(roomDef, assetBounds, {
    flatMax: tol.flatMax,
    extras: roomRules.extras,
    ...opts,
  });
  const meta = assetBounds.meta ?? {};
  const shell = meta.shell ?? SHELL_DIMS;
  const garden = meta.gardenSize ?? GARDEN_DIMS;
  const outdoor = !!roomDef.outdoor;
  const halfW = (outdoor ? garden.width : shell.width) / 2;
  const halfD = (outdoor ? garden.depth : shell.depth) / 2;
  const wallMounted = new Set(roomRules.wallMounted ?? []);
  const elevated = new Set(roomRules.elevated ?? []);
  const edgeAllow = new Set(roomRules.edgeAllow ?? []);
  const tiltAllow = new Set(roomRules.tiltAllow ?? []);

  /** @type {Warning[]} */
  const warnings = [];
  const warn = (type, a, msg, extra = {}) =>
    warnings.push({ type, room: roomDef.id, a: a.label, msg, ...extra });

  // ── clip: pairwise AABB interpenetration ─────────────────────────────────
  for (let i = 0; i < boxes.length; i += 1) {
    for (let j = i + 1; j < boxes.length; j += 1) {
      const a = boxes[i];
      const b = boxes[j];
      if (a.source === b.source && a.index === b.index) continue; // same entry (set pieces)
      const ox = overlap1D(a, b, 0);
      const oy = overlap1D(a, b, 1);
      const oz = overlap1D(a, b, 2);
      if (ox <= 0 || oy <= 0 || oz <= 0) continue;
      const pen = Math.min(ox, oy, oz);
      if (pen <= tol.clipTol) continue; // flush composition
      if (a.flat || b.flat) continue; // rugs/paths under anything
      const hi = a.min[1] >= b.min[1] ? a : b;
      const lo = hi === a ? b : a;
      if (hi.min[1] >= lo.max[1] - tol.stackGap) continue; // deliberate y-stack
      if (pairAllowed(roomRules.clipAllow, a, b)) continue;
      warn('clip', a, `${a.label} clips ${b.label} by ${pen.toFixed(3)} m`, {
        b: b.label, amount: +pen.toFixed(4),
      });
    }
  }

  for (const b of boxes) {
    const embedMax = wallMounted.has(b.key) ? tol.wallEmbedMax : tol.wallTol;

    // ── wall-penetration / out-of-shell ─────────────────────────────────────
    if (!outdoor) {
      const backPen = -halfD - b.min[2];
      if (backPen > embedMax) {
        warn('wall-penetration', b,
          `${b.label} crosses the back wall by ${backPen.toFixed(3)} m`,
          { amount: +backPen.toFixed(4) });
      }
      // side walls run from the back wall SIDE_DEPTH toward the camera
      const sideZmax = -halfD + shell.sideDepth;
      const inSideBand = b.min[2] < sideZmax && b.max[2] > -halfD;
      for (const [sign, name] of [[-1, 'left'], [1, 'right']]) {
        const pen = sign < 0 ? -halfW - b.min[0] : b.max[0] - halfW;
        if (pen <= (inSideBand ? embedMax : tol.edgeTol)) continue;
        if (inSideBand) {
          warn('wall-penetration', b,
            `${b.label} crosses the ${name} wall by ${pen.toFixed(3)} m`,
            { amount: +pen.toFixed(4) });
        } else {
          warn('out-of-shell', b,
            `${b.label} hangs ${pen.toFixed(3)} m past the floor's ${name} edge`,
            { amount: +pen.toFixed(4) });
        }
      }
      const frontPen = b.max[2] - halfD;
      if (frontPen > tol.edgeTol) {
        warn('out-of-shell', b,
          `${b.label} hangs ${frontPen.toFixed(3)} m past the floor's front edge`,
          { amount: +frontPen.toFixed(4) });
      }
    } else if (!edgeAllow.has(b.key)) {
      for (const [axis, half, name] of [[0, halfW, 'x'], [2, halfD, 'z']]) {
        const pen = Math.max(-half - b.min[axis], b.max[axis] - half);
        if (pen > tol.edgeTol) {
          warn('out-of-shell', b,
            `${b.label} extends ${pen.toFixed(3)} m past the garden ground (${name})`,
            { amount: +pen.toFixed(4) });
        }
      }
    }

    // ── float / sunk ─────────────────────────────────────────────────────────
    if (b.min[1] < tol.sunkMin) {
      warn('sunk', b, `${b.label} sinks ${(-b.min[1]).toFixed(3)} m into the floor`,
        { amount: +(-b.min[1]).toFixed(4) });
    }
    if (b.min[1] > tol.floatMax && !elevated.has(b.key)
      && !isSupported(b, boxes, tol.supportTol)) {
      warn('float', b,
        `${b.label} floats at y=${b.min[1].toFixed(3)} with nothing under it`,
        { amount: +b.min[1].toFixed(4) });
    }

    // ── tilt (data-level: roomManager only ever applies rotY) ───────────────
    if (b.rotXZ && !tiltAllow.has(b.key)) {
      warn('tilt', b,
        `${b.label} carries non-whitelisted rotX/rotZ [${b.rotXZ.join(', ')}]`);
    }

    // ── facing ───────────────────────────────────────────────────────────────
    const rule = roomRules.facing?.[b.key];
    if (rule) {
      if (!b.forward) {
        warn('facing', b, `${b.label} has a facing rule but no canonical forward in the fixture`);
      } else {
        let expectDir = null;
        let maxDeg;
        if (rule.mode === 'camera') {
          expectDir = [0, 1];
          maxDeg = rule.maxDeg ?? tol.cameraMaxDeg;
        } else if (rule.mode === 'target') {
          const cx = (b.min[0] + b.max[0]) / 2;
          const cz = (b.min[2] + b.max[2]) / 2;
          expectDir = [rule.at[0] - cx, rule.at[1] - cz];
          maxDeg = rule.maxDeg ?? tol.targetMaxDeg;
        } else if (rule.mode === 'vector') {
          expectDir = rule.dir;
          maxDeg = rule.maxDeg ?? tol.targetMaxDeg;
        }
        if (expectDir) {
          const off = angleDeg(b.forward, expectDir);
          if (off > maxDeg) {
            warn('facing', b,
              `${b.label} faces ${off.toFixed(0)}° off its expected direction (max ${maxDeg}°)`,
              { amount: +off.toFixed(1) });
          }
        }
        if (rule.wallBacked && !outdoor) {
          // the dominant back direction must meet a wall within backMax
          const bx = -b.forward[0];
          const bz = -b.forward[1];
          let gap = null;
          let wall = null;
          if (Math.abs(bz) >= Math.abs(bx)) {
            if (bz < 0) { gap = b.min[2] - -halfD; wall = 'back'; }
          } else if (bx < 0) { gap = b.min[0] - -halfW; wall = 'left'; }
          else { gap = halfW - b.max[0]; wall = 'right'; }
          if (gap == null) {
            warn('facing', b, `${b.label} is wall-backed but faces away from every wall`);
          } else if (gap > tol.backMax) {
            warn('facing', b,
              `${b.label} should back onto the ${wall} wall but stands ${gap.toFixed(3)} m off it`,
              { amount: +gap.toFixed(4) });
          }
        }
      }
    }
  }

  return warnings;
}

/**
 * Convenience: audit every def and return a room-id → warnings map (only
 * rooms with at least one warning appear).
 * @param {object[]} roomDefs @param {object} assetBounds @param {object} rules
 * @returns {Record<string, Warning[]>}
 */
export function auditAllRooms(roomDefs, assetBounds, rules = {}) {
  const out = {};
  for (const def of roomDefs) {
    const warnings = auditRoom(def, assetBounds, rules);
    if (warnings.length) out[def.id] = warnings;
  }
  return out;
}
