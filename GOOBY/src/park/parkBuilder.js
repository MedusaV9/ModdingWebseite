// V6/E1 — Funkelpark plaza builder (PLAN6 Wave E/E1): the pure seeded layout
// behind park/parkScene.js. Same architecture as city/cityBuilder.js: this
// module is PURE — no three.js/DOM imports — so test/parkLayout.test.js runs
// it headlessly under node:test. The exported layout is plain data: item
// placements with GLB asset keys AND axis-aligned world footprints (hw/hd
// half-extents — the zero-overlap contract, risk row 6), the path network,
// Gooby's stroll loop and the named tap/integration anchors. The three.js
// assembly lives in park/parkScene.js.
//
// Plaza-local coordinates: x grows east, z grows south, origin at the plaza
// center, ground at y = 0. The ENTRANCE GATE sits on the south edge (the car
// parks outside it — trip arrivals walk in heading north), Candy Alley
// (E3's 13.1 × 2.9 m strip, parkDressing.js) on the west side facing east,
// the coaster entrance kiosk north-east, and the RESERVED ferrisWheel anchor
// north-west (F4 lands there — named anchor + deliberately clear footprint).
// The coaster itself is a background silhouette OUTSIDE the plaza rim
// (drawn by parkScene, north of the kiosk — no plaza footprint).
//
// The layout is HAND-PLACED and identical for every seed except the rim
// trees/shrubs, which jitter from the seeded rng and are dropped rather than
// ever overlapping a placed footprint (the test proves zero overlaps AND
// cross-seed determinism of the fixed anchors).

import { createLayoutRng } from '../city/cityBuilder.js';
import { PARK_DRESSING } from './parkDressing.js'; // E3's measured FOOTPRINT

const DEG = Math.PI / 180;

/** §E0.1-2: binding plaza numbers live in the owning module (frozen). */
export const PARK_PLAZA = Object.freeze({
  /** plaza half-size (m) — items must keep their footprint inside ±HALF */
  HALF: 22,
  /** entrance gate castle scale (minigolf-kit/castle, authored 1×1×0.65) */
  GATE_SCALE: 6,
  /** fountain scale (pretty-park/fountain, authored 4×4 m) */
  FOUNTAIN_SCALE: 1.5,
  /** walk path ribbon width (m) */
  PATH_W: 3.2,
  /** rim tree ring radius (m) */
  TREE_RING_R: 19.5,
});

/**
 * Asset keys the plaza builds from (parkScene preloads these; E3's
 * mountParkDressing preloads its own PARK_DRESSING_ASSET_KEYS and E2's
 * startCoasterRide its COASTER_ASSET_KEYS).
 */
export const PARK_ASSET_KEYS = Object.freeze([
  'minigolf-kit/castle',
  'pretty-park/fountain',
  'pretty-park/bench',
  'pretty-park/street_lantern',
  'pretty-park/flower_A',
  'nature-kit/tree_default',
  'nature-kit/tree_pineRoundA',
  'kaykit-restaurant/wall_orderwindow', // coaster kiosk booth
  'city-kit-commercial/detail-awning-wide', // kiosk awning
]);

/**
 * @typedef {Object} ParkItem
 * @property {string} id unique item id
 * @property {'gate'|'alley'|'kiosk'|'reserved'|'fountain'|'bench'|'lantern'|'planter'|'tree'} kind
 * @property {string|null} key GLB asset key (null: built procedurally / by
 *   E3's dressing / reserved-empty)
 * @property {number} x @property {number} z plaza-local center (m)
 * @property {number} rotY radians
 * @property {number} scale uniform
 * @property {number} hw axis-aligned footprint half-width (x, m)
 * @property {number} hd axis-aligned footprint half-depth (z, m)
 */

/**
 * @typedef {Object} ParkLayout
 * @property {number} seed
 * @property {number} half plaza half-size (m)
 * @property {ParkItem[]} items every placed footprint (zero overlaps)
 * @property {Array<{id: string, pts: Array<{x: number, z: number}>, width: number}>} paths
 *   walkway ribbons (ground decals — walkable, no footprint)
 * @property {Array<{x: number, z: number}>} goobyPath Gooby's stroll loop
 * @property {{x: number, z: number, rotY: number}} entry Gooby's spawn just
 *   inside the gate (facing north into the plaza)
 * @property {{gate: ParkItem, candyAlley: ParkItem, coasterKiosk: ParkItem,
 *   ferrisWheel: ParkItem, fountain: ParkItem}} anchors named integration
 *   anchors (gate/kiosk/alley are tap anchors; ferrisWheel is F4's reserve)
 */

/** Axis-aligned footprint overlap (strict — touching edges is allowed). */
export function itemsOverlap(a, b) {
  return (
    Math.abs(a.x - b.x) < a.hw + b.hw &&
    Math.abs(a.z - b.z) < a.hd + b.hd
  );
}

/**
 * All overlapping item-id pairs of a layout — the zero-overlap acceptance
 * check (test/parkLayout.test.js expects []).
 * @param {ParkLayout} layout
 * @returns {Array<[string, string]>}
 */
export function overlappingPairs(layout) {
  const out = [];
  const items = layout.items;
  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      if (itemsOverlap(items[i], items[j])) out.push([items[i].id, items[j].id]);
    }
  }
  return out;
}

/**
 * Generate the plaza layout for a seed. Fixed anchors are seed-independent;
 * only the rim greenery jitters (and drops instead of overlapping).
 * @param {number} seed
 * @returns {ParkLayout}
 */
export function generateParkLayout(seed) {
  const P = PARK_PLAZA;
  const rng = createLayoutRng(seed);
  /** @type {ParkItem[]} */
  const items = [];

  // --- entrance gate (south edge, castle front facing north into the plaza)
  const gate = {
    id: 'gate',
    kind: 'gate',
    key: 'minigolf-kit/castle',
    x: 0,
    z: 17,
    rotY: 180 * DEG, // authored front (+z) → north (−z)
    scale: P.GATE_SCALE,
    hw: 0.5 * P.GATE_SCALE,
    hd: 0.5 * P.GATE_SCALE,
  };
  items.push(gate);

  // --- Candy Alley (E3's strip, west side, stalls facing east) -------------
  // mountParkDressing builds around its local origin with the row along
  // local x and stalls facing local +z; rotY 90° turns that front to +x
  // (east), so the world footprint swaps E3's measured width/depth.
  const alleyFp = PARK_DRESSING.FOOTPRINT; // { width: 13.1, depth: 2.9 }
  const candyAlley = {
    id: 'candyAlley',
    kind: 'alley',
    key: null, // E3's mountParkDressing owns the visuals
    x: -14,
    z: -1,
    rotY: 90 * DEG,
    scale: 1,
    hw: alleyFp.depth / 2,
    hd: alleyFp.width / 2,
  };
  items.push(candyAlley);

  // --- coaster entrance kiosk (north-east, booth facing south) -------------
  const coasterKiosk = {
    id: 'coasterKiosk',
    kind: 'kiosk',
    key: 'kaykit-restaurant/wall_orderwindow',
    x: 11,
    z: -11,
    rotY: 0, // authored front (+z) → south, toward the fountain plaza
    scale: 1.45,
    hw: 1.7,
    hd: 0.9,
  };
  items.push(coasterKiosk);

  // --- ferrisWheel anchor (north-west) — V6/F4's Riesenrad mounts here -----
  // The wheel itself is fully procedural (park/ferrisWheel.js — primitives +
  // instancing, no GLB), so kind/key STAY 'reserved'/null: parkScene parents
  // the build at this anchor and buildPlaza's key-instancing loop keeps
  // skipping it (test/parkLayout.test.js pins kind/key + the clear footprint).
  const ferrisWheel = {
    id: 'ferrisWheel',
    kind: 'reserved',
    key: null, // procedural — mounted by parkScene, never GLB-instanced
    x: -12,
    z: -15,
    // V6/F4: disc normal points at the plaza heart (atan2(12, 15) ≈ 38.7°),
    // so the south overview camera reads the wheel face in a 3/4 view
    // instead of edge-on (the old 90° suggestion).
    rotY: Math.atan2(12, 15),
    scale: 1,
    hw: 5.5,
    hd: 5.5,
  };
  items.push(ferrisWheel);

  // --- fountain (plaza heart) ----------------------------------------------
  const fountain = {
    id: 'fountain',
    kind: 'fountain',
    key: 'pretty-park/fountain',
    x: 0,
    z: -1,
    rotY: 0,
    scale: P.FOUNTAIN_SCALE,
    hw: 2 * P.FOUNTAIN_SCALE,
    hd: 2 * P.FOUNTAIN_SCALE,
  };
  items.push(fountain);

  // --- benches around the fountain (pretty-park/bench, 2×1.32 authored) ----
  const BENCH_SCALE = 1.2;
  const benches = [
    { id: 'benchW', x: -7.5, z: -1, rotY: -90 * DEG }, // seat faces east → fountain
    { id: 'benchE', x: 7.5, z: -1, rotY: 90 * DEG }, //  seat faces west → fountain
    { id: 'benchN', x: 0, z: -9, rotY: 0 }, //            seat faces south → fountain
  ];
  for (const b of benches) {
    const rot90 = b.rotY !== 0;
    items.push({
      ...b,
      kind: 'bench',
      key: 'pretty-park/bench',
      scale: BENCH_SCALE,
      hw: (rot90 ? 0.66 : 1) * BENCH_SCALE,
      hd: (rot90 ? 1 : 0.66) * BENCH_SCALE,
    });
  }

  // --- lanterns (pretty-park/street_lantern, 0.94 m square base) -----------
  const LANTERN_SCALE = 1.1;
  const lanterns = [
    { id: 'lanternGateW', x: -3.4, z: 10.5 },
    { id: 'lanternGateE', x: 3.4, z: 10.5 },
    { id: 'lanternSW', x: -8, z: 6 },
    { id: 'lanternSE', x: 8, z: 6 },
    { id: 'lanternNW', x: -5.5, z: -8.5 },
    { id: 'lanternNE', x: 5.5, z: -8.5 },
  ];
  for (const l of lanterns) {
    items.push({
      ...l,
      kind: 'lantern',
      key: 'pretty-park/street_lantern',
      rotY: 0,
      scale: LANTERN_SCALE,
      hw: 0.47 * LANTERN_SCALE,
      hd: 0.47 * LANTERN_SCALE,
    });
  }

  // --- flower planters (pretty-park/flower_A) -------------------------------
  const PLANTER_SCALE = 1.6;
  const planters = [
    { id: 'planterSW', x: -5.2, z: 3.6 },
    { id: 'planterSE', x: 5.2, z: 3.6 },
    { id: 'planterNW', x: -5.2, z: -5.6 },
    { id: 'planterNE', x: 5.2, z: -5.6 },
  ];
  for (const p of planters) {
    items.push({
      ...p,
      kind: 'planter',
      key: 'pretty-park/flower_A',
      rotY: rng() * Math.PI * 2,
      scale: PLANTER_SCALE,
      hw: 0.23 * PLANTER_SCALE,
      hd: 0.23 * PLANTER_SCALE,
    });
  }

  // --- rim greenery (seeded jitter; drop instead of overlap) ----------------
  // A ring of trees just inside the plaza edge, skipping the south gate arc.
  const TREE_KEYS = ['nature-kit/tree_default', 'nature-kit/tree_pineRoundA'];
  let treeN = 0;
  for (let a = 0; a < 360; a += 24) {
    // skip the gate arc (south = +z → angles around 90° in this parametrization)
    if (a > 55 && a < 125) continue;
    const ang = a * DEG;
    const r = P.TREE_RING_R + (rng() - 0.5) * 2.2;
    const scale = 3.4 + rng() * 1.4;
    const tree = {
      id: `tree${treeN}`,
      kind: 'tree',
      key: TREE_KEYS[Math.floor(rng() * TREE_KEYS.length)],
      x: Math.cos(ang) * r,
      z: Math.sin(ang) * r,
      rotY: rng() * Math.PI * 2,
      scale,
      hw: 0.16 * scale, // trunk footprint (canopies may kiss — trunks never)
      hd: 0.16 * scale,
    };
    // keep the footprint fully inside the plaza and off every placed item
    if (
      Math.abs(tree.x) + tree.hw > P.HALF ||
      Math.abs(tree.z) + tree.hd > P.HALF ||
      items.some((it) => itemsOverlap(it, tree))
    ) {
      continue;
    }
    items.push(tree);
    treeN += 1;
  }

  // --- path network (ground ribbons — walkable, no footprint) ---------------
  const paths = [
    // gate → fountain (the arrival spine)
    { id: 'spine', pts: [{ x: 0, z: 14 }, { x: 0, z: 3.4 }], width: P.PATH_W },
    // fountain ring west → Candy Alley front
    { id: 'toAlley', pts: [{ x: -3.4, z: -1 }, { x: -11.5, z: -1 }], width: P.PATH_W },
    // fountain ring east → coaster kiosk
    { id: 'toCoaster', pts: [{ x: 3, z: -3 }, { x: 11, z: -9 }], width: P.PATH_W },
    // fountain ring north-west → ferris wheel reserve (F4's approach)
    { id: 'toWheel', pts: [{ x: -3, z: -3.4 }, { x: -9.5, z: -8.6 }], width: P.PATH_W },
  ];

  // --- Gooby ------------------------------------------------------------------
  const entry = { x: 0, z: 11.5, rotY: 180 * DEG }; // just inside the gate, facing north
  // stroll loop around the fountain (clear of every footprint above)
  const goobyPath = [
    { x: 0, z: 6 },
    { x: 4.6, z: 2.2 },
    { x: 5.6, z: -3.6 },
    { x: 0, z: -6.4 },
    { x: -5.6, z: -3.6 },
    { x: -4.6, z: 2.2 },
  ];

  return {
    seed,
    half: P.HALF,
    items,
    paths,
    goobyPath,
    entry,
    anchors: { gate, candyAlley, coasterKiosk, ferrisWheel, fountain },
  };
}
