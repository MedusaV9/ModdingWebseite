// V6/E3 (PLAN6 Wave E): Funkelpark „Candy Alley" — the food-stall strip and
// the night-lights „Lichterfest" dressing. Three striped stalls (KayKit
// restaurant order-window walls + Kenney city-kit awnings + food-kit counter
// props + a procedural cotton-candy puff), CanvasTexture stall signage
// (t()-resolved EN/DE), procedural bunting (sagging string spans with tiny
// instanced pennants) and a two-draw-call night layer (one InstancedMesh of
// emissive-look bulbs along bunting/awning edges + lantern heads, one
// InstancedMesh of additive glow quads for warm window light and lantern
// halos), plus pretty-park lantern posts at the alley ends.
//
// Integration contract (frozen at wave start — E1's parkScene.js wires the
// plaza against these exports; see /tmp handoff E3-exports-for-E1.txt):
//   mountParkDressing(sceneGroup, band) → Promise<{group, setBand, dispose}>
//   setBand(band)                         module-level forwarder
// `band` is a systems/dayNight.js BANDS id ('day'|'dawn'|'dusk'|'night');
// lights are on for dusk + night (bandVisual). Materials swap ONCE per band
// change (current-band guard) and the night layer adds ≤ NIGHT_LAYER_DRAW_
// CALLS (= 2) draw calls — the PLAN6 E3 budget, pinned by the swapPlan model
// in test/parkAttractions.test.js.
//
// MODULE LEVEL IS PURE — three.js and core/assets.js load dynamically inside
// mountParkDressing (the shopScreen decor-boot rule), so node:test can import
// the layout consts and pure helpers headlessly. Grounding follows the
// V4/FIX-3D lesson: every GLB is measured ONCE with Box3 at build and snapped
// so its scaled bbox min sits on the ground (groundOffset); counter planes
// sit at the measured wall front face + COUNTER_CLEARANCE_M (2 cm) against
// z-fighting (plan acceptance), and counter props stack on the measured
// counter top the same way.

import { t, getLang } from '../data/strings.js';
// V6/E3: strings.js is frozen (§E0.1-8) — E1 commits the v6-park import pair;
// until then keys resolve through the local tx() fallback (G52 precedent).
import { EN as PARK_EN, DE as PARK_DE } from '../data/strings/v6-park.js';

/** t() first, then the owned v6-park EN/DE table (shopScreen tx() pattern). */
function tx(key) {
  const v = t(key);
  if (v !== key) return v;
  return (getLang() === 'de' ? PARK_DE : PARK_EN)[key] ?? key;
}

// ---------------------------------------------------------------------------
// Frozen layout/tuning consts (§E0.1-2: park numbers live in owning modules)
// ---------------------------------------------------------------------------

export const PARK_DRESSING = Object.freeze({
  /** stall center-to-center spacing along local x (m) */
  STALL_SPACING_M: 3.4,
  /** uniform scale for the KayKit restaurant wall pieces */
  STALL_SCALE: 1.45,
  /** counter plane clearance off the measured wall front face (m — the
   *  binding “+2 cm against z-fighting” acceptance number) */
  COUNTER_CLEARANCE_M: 0.02,
  /** counter plane size (m) — spans most of a stall front */
  COUNTER_W_M: 1.7,
  COUNTER_D_M: 0.34,
  COUNTER_T_M: 0.05,
  /** counter top height as a fraction of the scaled wall height (the
   *  order-window sill line of wall_orderwindow, verified visually) */
  COUNTER_H_FRACTION: 0.47,
  /** bunting sag depth (m) and polyline resolution per span */
  BUNTING_SAG_M: 0.32,
  BUNTING_SEGMENTS: 16,
  PENNANTS_PER_SPAN: 7,
  BULBS_PER_SPAN: 11,
  BULBS_PER_AWNING: 5,
  /** whole-alley footprint for E1's zero-overlap plaza layout test (m) —
   *  MEASURED from the mounted group's bbox (lantern post to lantern post,
   *  wall back face to the front crates), not estimated */
  FOOTPRINT: Object.freeze({ width: 13.1, depth: 2.9 }),
  GROUND_Y: 0,
});

/** Night layer draw-call budget (PLAN6 E3 acceptance: ≤ 2 added calls). */
export const NIGHT_LAYER_DRAW_CALLS = 2;

/**
 * The three Candy Alley stalls. `foodId` rows live in data/foods.js
 * (V6_PARK_FOODS, park: true); `signKey` resolves through tx() for the
 * CanvasTexture signage AND the parkStall sheet; `tint` colors the awning
 * (instance color) and sign plate, `accent` the pennant/sign text pairing.
 * @type {ReadonlyArray<{id: string, foodId: string, signKey: string,
 *   tint: string, accent: string}>}
 */
export const PARK_STALLS = Object.freeze([
  Object.freeze({
    id: 'cottonCandy',
    foodId: 'cottonCandy',
    signKey: 'park.stall.cottonCandy.name',
    tint: '#F781B0',
    accent: '#FFF6EC',
  }),
  Object.freeze({
    id: 'softServe',
    foodId: 'softServe',
    signKey: 'park.stall.softServe.name',
    tint: '#9BD7E8',
    accent: '#FFF6EC',
  }),
  Object.freeze({
    id: 'waffle',
    foodId: 'waffle',
    signKey: 'park.stall.waffle.name',
    tint: '#F5C518',
    accent: '#4A3B36',
  }),
]);

/** GLB keys the dressing preloads (E1 may preload earlier — same cache). */
export const PARK_DRESSING_ASSET_KEYS = Object.freeze([
  'kaykit-restaurant/wall_orderwindow',
  'kaykit-restaurant/menu',
  'kaykit-restaurant/crate_buns',
  'kaykit-restaurant/jar_A_large',
  'city-kit-commercial/detail-awning-wide',
  'food-kit/ice-cream',
  'food-kit/waffle',
  'pretty-park/street_lantern',
]);

// ---------------------------------------------------------------------------
// Pure helpers (the node:test surface — no three.js, no DOM)
// ---------------------------------------------------------------------------

/**
 * Grounding offset: how far to lift (or sink) a placement so the SCALED bbox
 * min face sits exactly on the ground plane (V4/FIX-3D gazebo lesson —
 * bounds-grounded, never eyeballed).
 * @param {number} scaledMinY the model's bbox min.y AFTER scaling
 * @param {number} [groundY] ground plane height (default 0)
 * @returns {number} y translation that puts bbox.min.y onto groundY
 */
export function groundOffset(scaledMinY, groundY = PARK_DRESSING.GROUND_Y) {
  return groundY - scaledMinY;
}

/**
 * Counter plane z: the measured wall front face + the binding 2 cm clearance
 * (anti z-fighting acceptance). Pure so the test pins the exact offset.
 * @param {number} wallFrontZ the wall's scaled bbox max.z (front face)
 * @param {number} [clearance]
 * @returns {number}
 */
export function counterPlaneZ(wallFrontZ, clearance = PARK_DRESSING.COUNTER_CLEARANCE_M) {
  return wallFrontZ + clearance;
}

/**
 * Sagging bunting span between two anchor points: straight-line lerp with a
 * parabolic dip (max `sag` at t = 0.5, exact endpoints at t = 0/1) — the
 * catmull-through-sagged-midpoint shape without needing three.js in tests.
 * @param {{x:number,y:number,z:number}} a
 * @param {{x:number,y:number,z:number}} b
 * @param {number} [segments] polyline resolution (≥ 1)
 * @param {number} [sag] dip depth in meters
 * @returns {{x:number,y:number,z:number}[]} segments+1 points, a → b
 */
export function buntingPoints(
  a,
  b,
  segments = PARK_DRESSING.BUNTING_SEGMENTS,
  sag = PARK_DRESSING.BUNTING_SAG_M
) {
  const n = Math.max(1, Math.floor(segments));
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const s = i / n;
    pts.push({
      x: a.x + (b.x - a.x) * s,
      y: a.y + (b.y - a.y) * s - sag * 4 * s * (1 - s),
      z: a.z + (b.z - a.z) * s,
    });
  }
  return pts;
}

/**
 * Evenly spaced interior spots along a bunting span (for pennants/bulbs) —
 * never on the anchor endpoints.
 * @param {{x:number,y:number,z:number}} a
 * @param {{x:number,y:number,z:number}} b
 * @param {number} count
 * @param {number} [sag]
 * @returns {{x:number,y:number,z:number}[]}
 */
export function buntingSpots(a, b, count, sag = PARK_DRESSING.BUNTING_SAG_M) {
  const spots = [];
  for (let i = 0; i < count; i++) {
    const s = (i + 1) / (count + 1);
    spots.push({
      x: a.x + (b.x - a.x) * s,
      y: a.y + (b.y - a.y) * s - sag * 4 * s * (1 - s),
      z: a.z + (b.z - a.z) * s,
    });
  }
  return spots;
}

/**
 * Pure band → visual state model (which dayNight band lights the alley).
 * @param {'day'|'dawn'|'dusk'|'night'|string} band
 * @returns {{night: boolean}}
 */
export function bandVisual(band) {
  return Object.freeze({ night: band === 'dusk' || band === 'night' });
}

/**
 * Pure band-swap bookkeeping — the setBand contract as data, pinned by
 * test/parkAttractions.test.js:
 *   · same band → no-op (materials swap ONCE per band change);
 *   · night-state toggle costs exactly NIGHT_LAYER_DRAW_CALLS extra calls
 *     when turning on, −NIGHT_LAYER_DRAW_CALLS when turning off;
 *   · a band change within the same night state (day→dawn, dusk→night)
 *     swaps materials but adds zero calls.
 * @param {string} prevBand
 * @param {string} nextBand
 * @returns {{changed: boolean, nightToggled: boolean, nightCallsDelta: number}}
 */
export function swapPlan(prevBand, nextBand) {
  const changed = prevBand !== nextBand;
  const wasNight = bandVisual(prevBand).night;
  const isNight = bandVisual(nextBand).night;
  const nightToggled = changed && wasNight !== isNight;
  return Object.freeze({
    changed,
    nightToggled,
    nightCallsDelta: nightToggled ? (isNight ? NIGHT_LAYER_DRAW_CALLS : -NIGHT_LAYER_DRAW_CALLS) : 0,
  });
}

// ---------------------------------------------------------------------------
// Runtime (browser only — three.js/core/assets via dynamic import)
// ---------------------------------------------------------------------------

/** @type {{setBand: (band: string) => void, dispose: () => void}|null} */
let activeDressing = null;

/**
 * Module-level band forwarder (frozen E1 contract): applies the band to the
 * most recently mounted dressing; harmless no-op when nothing is mounted.
 * @param {'day'|'dawn'|'dusk'|'night'|string} band
 */
export function setBand(band) {
  activeDressing?.setBand(band);
}

/**
 * Build + mount the Candy Alley dressing group into `sceneGroup` and apply
 * the initial band. Local origin = center of the stall strip, stalls facing
 * +z, row along x, ground at local y = 0 (position/rotate the returned
 * handle.group to place it in the plaza; footprint in PARK_DRESSING).
 * Fail-soft: missing GLBs resolve to asset-cache placeholders (never throws).
 * @param {import('three').Object3D} sceneGroup parent (plaza group or scene)
 * @param {'day'|'dawn'|'dusk'|'night'|string} band initial dayNight band
 * @returns {Promise<{group: import('three').Group,
 *   setBand: (band: string) => void, dispose: () => void}>}
 */
export async function mountParkDressing(sceneGroup, band) {
  const THREE = await import('three');
  const assets = await import('../core/assets.js');
  try {
    await assets.preload([...PARK_DRESSING_ASSET_KEYS]);
  } catch (err) {
    console.warn('[parkDressing] preload incomplete — placeholders will fill in:', err);
  }

  const D = PARK_DRESSING;
  const group = new THREE.Group();
  group.name = 'parkDressing';

  /** resources created HERE (disposed on dispose(); shared cache masters —
   * assets.isCachedResource — are never touched) */
  /** @type {Array<{dispose: () => void}>} */
  const owned = [];
  const own = (res) => {
    if (res && !assets.isCachedResource(res)) owned.push(res);
    return res;
  };

  const tmpM = new THREE.Matrix4();
  const tmpQ = new THREE.Quaternion();
  const Y_AXIS = new THREE.Vector3(0, 1, 0);
  const composeAt = (x, y, z, rotY, scale) => {
    tmpQ.setFromAxisAngle(Y_AXIS, rotY ?? 0);
    return new THREE.Matrix4().compose(
      new THREE.Vector3(x, y, z),
      tmpQ,
      new THREE.Vector3(scale, scale, scale)
    );
  };

  /**
   * cityDrive addInstanced pattern: every mesh of a (possibly multi-mesh)
   * GLB master as InstancedMesh — one call per (geometry, material) pair.
   * Optional per-instance tints via setColorAt.
   * @returns {import('three').InstancedMesh[]}
   */
  const addInstanced = (model, transforms, tints = null, materialOverride = null) => {
    const meshes = [];
    if (transforms.length === 0) return meshes;
    model.updateMatrixWorld(true);
    model.traverse((o) => {
      if (!o.isMesh) return;
      const im = new THREE.InstancedMesh(o.geometry, materialOverride ?? o.material, transforms.length);
      for (let i = 0; i < transforms.length; i++) {
        tmpM.multiplyMatrices(transforms[i], o.matrixWorld);
        im.setMatrixAt(i, tmpM);
        if (tints) im.setColorAt(i, new THREE.Color(tints[i % tints.length]));
      }
      im.instanceMatrix.needsUpdate = true;
      if (im.instanceColor) im.instanceColor.needsUpdate = true;
      group.add(im);
      meshes.push(im);
    });
    return meshes;
  };

  /** Measure a master clone ONCE (bounds-grounding source of truth). */
  const measure = (key) => {
    const model = assets.getModel(key);
    const box = new THREE.Box3().setFromObject(model);
    return { model, box };
  };

  // ── stalls: order-window walls, bounds-grounded ─────────────────────────
  const stallX = (i) => (i - (PARK_STALLS.length - 1) / 2) * D.STALL_SPACING_M;
  const wall = measure('kaykit-restaurant/wall_orderwindow');
  const S = D.STALL_SCALE;
  const wallLift = groundOffset(wall.box.min.y * S);
  const wallTopY = wall.box.max.y * S + wallLift;
  const wallFrontZ = wall.box.max.z * S; // stalls face +z (local)
  addInstanced(
    wall.model,
    PARK_STALLS.map((_, i) => composeAt(stallX(i), wallLift, 0, 0, S))
  );

  // ── counter planes at the measured front face + 2 cm (plan acceptance) ──
  const counterTopY = wallTopY * D.COUNTER_H_FRACTION;
  const counterZ = counterPlaneZ(wallFrontZ) + D.COUNTER_D_M / 2;
  const counterGeo = own(new THREE.BoxGeometry(D.COUNTER_W_M, D.COUNTER_T_M, D.COUNTER_D_M));
  const counterMat = own(new THREE.MeshLambertMaterial({ color: '#C98A4B' }));
  {
    const counters = new THREE.InstancedMesh(counterGeo, counterMat, PARK_STALLS.length);
    PARK_STALLS.forEach((_, i) => {
      counters.setMatrixAt(
        i,
        composeAt(stallX(i), counterTopY - D.COUNTER_T_M / 2, counterZ, 0, 1)
      );
    });
    counters.instanceMatrix.needsUpdate = true;
    group.add(counters);
  }

  // ── awnings (city-kit-commercial detail-awning-wide, per-stall tint) ────
  // White-base material override so the per-instance pastel tints render
  // clean (setColorAt MULTIPLIES the base material — the GLB's own dark
  // awning color muddied the candy palette; dev-verified).
  const awning = measure('city-kit-commercial/detail-awning-wide');
  const awningScale = (D.STALL_SPACING_M * 0.62) /
    Math.max(0.001, awning.box.max.x - awning.box.min.x);
  const awningLift = -awning.box.min.y * awningScale; // hang line at its bbox base
  const awningBaseY = wallTopY * 0.86;
  const awningTopY = awningBaseY + (awning.box.max.y - awning.box.min.y) * awningScale;
  addInstanced(
    awning.model,
    PARK_STALLS.map((_, i) =>
      composeAt(stallX(i), awningBaseY + awningLift, wallFrontZ + 0.01, 0, awningScale)
    ),
    PARK_STALLS.map((s) => s.tint),
    own(new THREE.MeshLambertMaterial({ color: '#FFFFFF' }))
  );

  // ── stall signage: CanvasTexture name boards above the awnings ──────────
  // Above the MEASURED awning top (+ margin) — a fixed wallTopY offset left
  // the boards half-hidden behind the awning bar (dev-verified).
  const signY = Math.max(wallTopY, awningTopY) + 0.3;
  const signs = [];
  if (typeof document !== 'undefined') {
    for (let i = 0; i < PARK_STALLS.length; i++) {
      const stall = PARK_STALLS[i];
      const canvas = document.createElement('canvas');
      canvas.width = 512;
      canvas.height = 128;
      const g = canvas.getContext('2d');
      g.fillStyle = stall.tint;
      g.beginPath();
      if (typeof g.roundRect === 'function') g.roundRect(4, 4, 504, 120, 26);
      else g.rect(4, 4, 504, 120);
      g.fill();
      g.lineWidth = 8;
      g.strokeStyle = 'rgba(255,255,255,0.85)';
      g.stroke();
      g.font = '900 58px system-ui, sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillStyle = stall.accent;
      g.fillText(tx(stall.signKey), 256, 68, 470);
      const tex = own(new THREE.CanvasTexture(canvas));
      tex.colorSpace = THREE.SRGBColorSpace;
      const mat = own(new THREE.MeshBasicMaterial({ map: tex, transparent: true }));
      const geo = own(new THREE.PlaneGeometry(1.6, 0.4));
      const sign = new THREE.Mesh(geo, mat);
      sign.position.set(stallX(i), signY, wallFrontZ + 0.02);
      group.add(sign);
      signs.push(sign);
    }
  }

  // ── counter props (bounds-grounded ON the measured counter top) ─────────
  const propY = counterTopY + 0.001; // counter top face; each prop grounds its bbox
  const placeProps = (key, spots, scale) => {
    const { model, box } = measure(key);
    const lift = groundOffset(box.min.y * scale, propY);
    addInstanced(
      model,
      spots.map(({ x, z, rotY }) => composeAt(x, lift, z, rotY ?? 0, scale))
    );
  };
  // softServe stall (index 1): two cones on the counter
  placeProps('food-kit/ice-cream', [
    { x: stallX(1) - 0.28, z: counterZ - 0.02, rotY: 0.4 },
    { x: stallX(1) + 0.3, z: counterZ + 0.04, rotY: -0.7 },
  ], 1.1);
  // waffle stall (index 2): two waffles (cartoon-big so they read from the
  // alley camera distance — the flat GLB vanished at prop scale)
  placeProps('food-kit/waffle', [
    { x: stallX(2) - 0.32, z: counterZ, rotY: 0.9 },
    { x: stallX(2) + 0.3, z: counterZ + 0.03, rotY: -0.4 },
  ], 1.4);
  // cottonCandy stall (index 0): procedural pink puffs on sticks (no GLB —
  // IcosahedronGeometry with vertex jitter, the idea-02 §5 recipe)
  {
    const puffGeo = own(new THREE.IcosahedronGeometry(0.14, 1));
    const pos = puffGeo.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const j = 1 + ((i * 37) % 11) * 0.016; // deterministic jitter (no RNG dep)
      pos.setXYZ(i, pos.getX(i) * j, pos.getY(i) * j, pos.getZ(i) * j);
    }
    puffGeo.computeVertexNormals();
    const puffMat = own(new THREE.MeshLambertMaterial({ color: '#F9AFC6' }));
    const stickGeo = own(new THREE.CylinderGeometry(0.014, 0.014, 0.34, 5));
    const stickMat = own(new THREE.MeshLambertMaterial({ color: '#FFF6EC' }));
    const spots = [
      { x: stallX(0) - 0.38, z: counterZ - 0.02 },
      { x: stallX(0) + 0.4, z: counterZ + 0.04 },
    ];
    const puffs = new THREE.InstancedMesh(puffGeo, puffMat, spots.length);
    const sticks = new THREE.InstancedMesh(stickGeo, stickMat, spots.length);
    spots.forEach(({ x, z }, i) => {
      sticks.setMatrixAt(i, composeAt(x, propY + 0.17, z, 0, 1));
      puffs.setMatrixAt(i, composeAt(x, propY + 0.44, z, i * 1.7, 1.5));
    });
    puffs.instanceMatrix.needsUpdate = true;
    sticks.instanceMatrix.needsUpdate = true;
    group.add(puffs, sticks);
  }

  // ── side dressing: menu boards + crates/jars, bounds-grounded ───────────
  {
    const { model, box } = measure('kaykit-restaurant/menu');
    const lift = groundOffset(box.min.y * S);
    addInstanced(model, [
      composeAt(stallX(0) - 1.15, lift, wallFrontZ + 0.5, 0.35, S),
      composeAt(stallX(2) + 1.15, lift, wallFrontZ + 0.5, -0.35, S),
    ]);
  }
  {
    // Bun crates flank the stall GAPS at prop scale — the wall scale S made
    // them alley-blocking monsters overlapping at center (dev-verified).
    const crateScale = 0.8;
    const { model, box } = measure('kaykit-restaurant/crate_buns');
    const lift = groundOffset(box.min.y * crateScale);
    addInstanced(model, [
      composeAt(stallX(1) - D.STALL_SPACING_M / 2, lift, wallFrontZ + 0.45, 0.5, crateScale),
      composeAt(stallX(1) + D.STALL_SPACING_M / 2, lift, wallFrontZ + 0.38, -0.85, crateScale),
    ]);
  }
  {
    const { model, box } = measure('kaykit-restaurant/jar_A_large');
    const lift = groundOffset(box.min.y * S, propY);
    addInstanced(model, [composeAt(stallX(0) + 0.02, lift, counterZ - 0.05, 0.2, S)]);
  }

  // ── lantern posts (pretty-park GLB) at the alley ends ────────────────────
  const lantern = measure('pretty-park/street_lantern');
  const lanternScale = 1.0;
  const lanternLift = groundOffset(lantern.box.min.y * lanternScale);
  const lanternTopY = lantern.box.max.y * lanternScale + lanternLift;
  const lanternXs = [stallX(0) - D.STALL_SPACING_M * 0.78, stallX(2) + D.STALL_SPACING_M * 0.78];
  addInstanced(
    lantern.model,
    lanternXs.map((x) => composeAt(x, lanternLift, wallFrontZ + 0.85, 0, lanternScale))
  );

  // ── bunting: sagging spans stall-top → stall-top → lantern posts ────────
  const buntingY = signY + 0.42; // clear of the raised sign boards
  const buntingAnchors = [
    { x: lanternXs[0], y: lanternTopY - 0.06, z: wallFrontZ + 0.85 },
    { x: stallX(0), y: buntingY, z: wallFrontZ + 0.1 },
    { x: stallX(1), y: buntingY, z: wallFrontZ + 0.1 },
    { x: stallX(2), y: buntingY, z: wallFrontZ + 0.1 },
    { x: lanternXs[1], y: lanternTopY - 0.06, z: wallFrontZ + 0.85 },
  ];
  const spans = [];
  for (let i = 0; i < buntingAnchors.length - 1; i++) {
    spans.push([buntingAnchors[i], buntingAnchors[i + 1]]);
  }
  {
    // one LineSegments for ALL spans (1 draw call)
    const verts = [];
    for (const [a, b] of spans) {
      const pts = buntingPoints(a, b);
      for (let i = 0; i < pts.length - 1; i++) {
        verts.push(pts[i].x, pts[i].y, pts[i].z, pts[i + 1].x, pts[i + 1].y, pts[i + 1].z);
      }
    }
    const geo = own(new THREE.BufferGeometry());
    geo.setAttribute('position', new THREE.Float32BufferAttribute(verts, 3));
    const mat = own(new THREE.LineBasicMaterial({ color: '#8A6B4A' }));
    group.add(new THREE.LineSegments(geo, mat));
  }
  {
    // tiny instanced pennants along every span (1 draw call, pastel tints)
    const spots = spans.flatMap(([a, b]) => buntingSpots(a, b, D.PENNANTS_PER_SPAN));
    const geo = own(new THREE.ConeGeometry(0.065, 0.2, 4, 1, true));
    const mat = own(new THREE.MeshLambertMaterial({ side: THREE.DoubleSide }));
    const pennants = new THREE.InstancedMesh(geo, mat, spots.length);
    const palette = ['#F781B0', '#F5C518', '#9BD7E8', '#7ECB6F', '#FFF6EC'];
    spots.forEach((p, i) => {
      // apex-down triangle hanging just under the string
      pennants.setMatrixAt(i, composeAt(p.x, p.y - 0.09, p.z, (i % 5) * 0.12, 1));
      pennants.setColorAt(i, new THREE.Color(palette[i % palette.length]));
    });
    pennants.instanceMatrix.needsUpdate = true;
    if (pennants.instanceColor) pennants.instanceColor.needsUpdate = true;
    group.add(pennants);
  }

  // ── night layer: ≤ 2 draw calls (bulbs + glow quads), band-toggled ───────
  // Call 1: ONE InstancedMesh of emissive-look bulbs — along every bunting
  // span, along each awning front edge, and one per lantern head.
  const bulbSpots = [
    ...spans.flatMap(([a, b]) => buntingSpots(a, b, D.BULBS_PER_SPAN)),
    ...PARK_STALLS.flatMap((_, i) => {
      const edge = [];
      for (let k = 0; k < D.BULBS_PER_AWNING; k++) {
        const s = (k + 0.5) / D.BULBS_PER_AWNING;
        edge.push({
          x: stallX(i) + (s - 0.5) * D.STALL_SPACING_M * 0.58,
          y: awningBaseY - 0.03,
          z: wallFrontZ + 0.16,
        });
      }
      return edge;
    }),
    ...lanternXs.map((x) => ({ x, y: lanternTopY - 0.12, z: wallFrontZ + 0.85 })),
  ];
  const bulbGeo = own(new THREE.SphereGeometry(0.035, 6, 5));
  const bulbMat = own(new THREE.MeshBasicMaterial({ color: '#FFE9A8' }));
  const bulbs = new THREE.InstancedMesh(bulbGeo, bulbMat, bulbSpots.length);
  bulbSpots.forEach((p, i) => bulbs.setMatrixAt(i, composeAt(p.x, p.y, p.z, 0, 1)));
  bulbs.instanceMatrix.needsUpdate = true;
  group.add(bulbs);

  // Call 2: ONE InstancedMesh of additive glow quads — warm order-window
  // glow per stall + a halo per lantern head (radial gradient CanvasTexture).
  let glow = null;
  if (typeof document !== 'undefined') {
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 64;
    const g = canvas.getContext('2d');
    const grad = g.createRadialGradient(32, 32, 2, 32, 32, 32);
    grad.addColorStop(0, 'rgba(255,214,140,0.9)');
    grad.addColorStop(1, 'rgba(255,214,140,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, 64, 64);
    const tex = own(new THREE.CanvasTexture(canvas));
    const mat = own(new THREE.MeshBasicMaterial({
      map: tex,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    }));
    const geo = own(new THREE.PlaneGeometry(1, 1));
    const glowSpots = [
      ...PARK_STALLS.map((_, i) => ({
        x: stallX(i), y: counterTopY + 0.42, z: wallFrontZ + 0.04, s: 1.35,
      })),
      ...lanternXs.map((x) => ({
        x, y: lanternTopY - 0.12, z: wallFrontZ + 0.9, s: 0.8,
      })),
    ];
    glow = new THREE.InstancedMesh(geo, mat, glowSpots.length);
    glowSpots.forEach((p, i) => {
      tmpQ.identity();
      glow.setMatrixAt(i, new THREE.Matrix4().compose(
        new THREE.Vector3(p.x, p.y, p.z),
        tmpQ,
        new THREE.Vector3(p.s, p.s, p.s)
      ));
    });
    glow.instanceMatrix.needsUpdate = true;
    group.add(glow);
  }

  // ── band state: shared materials swap ONCE per band change ──────────────
  let currentBand = null;
  const applyBand = (nextBand) => {
    if (nextBand === currentBand) return; // swap once per band change
    currentBand = nextBand;
    const { night } = bandVisual(nextBand);
    bulbs.visible = night; // +1 call at night, 0 by day
    if (glow) glow.visible = night; // +1 call at night, 0 by day
    // warm the string + sign plates slightly after dark (shared materials —
    // ONE mutation per swap, never per mesh/frame)
    bulbMat.color.set(night ? '#FFD97A' : '#FFE9A8');
    for (const sign of signs) sign.material.color.set(night ? '#FFE9C9' : '#FFFFFF');
  };
  applyBand(band ?? 'day');

  sceneGroup.add(group);

  const handle = {
    group,
    setBand: applyBand,
    dispose() {
      if (activeDressing === handle) activeDressing = null;
      group.parent?.remove(group);
      for (const res of owned) res.dispose?.();
      owned.length = 0;
    },
  };
  activeDressing = handle;
  return handle;
}
