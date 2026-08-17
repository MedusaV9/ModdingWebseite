// V6.1/G2 (A3 — FINAL-WAVE 'souvenir shelf'): travel keepsakes as furniture.
// A fixed wall shelf in the living room shows ONE distinct procedural mini
// per visited vacation destination — the physical daily-view record of
// travel progress. No new GLBs/textures: every mini is a handful of
// vertex-colored three.js primitives, and the WHOLE shelf (plank + backboard
// + every earned mini) merges into ONE geometry/material draw call.
//
// Data contract (FROZEN, G1-owned): `vacation.sliceOf(state).visited` — a
// normalized map of KNOWN destination ids → true. This module never writes
// vacation state and tolerates the map missing entirely (pre-G1 saves /
// mid-wave merges): `readVisited` falls back to the raw slice field and
// re-normalizes through the recipe ids either way, so unknown/junk ids never
// build objects.
//
// Rebuild discipline: `createSouvenirShelf` re-merges ONLY when the
// normalized visited-id signature changes (roomManager subscribes it to the
// store's coalesced 'change' event) and disposes the previous geometry on
// every rebuild + on dispose(). The material is created once and disposed
// once. States 0/1/4/9 are deterministic — each destination owns a fixed
// shelf slot (VACATION_IDS order), so a mini never moves when its neighbours
// appear.
//
// Envelope invariant (audit contract): the backboard rises HIGHER than the
// tallest mini and the plank is deeper/wider than any mini footprint, so the
// shelf's AABB is IDENTICAL with 0 or 9 minis. scripts/gen-asset-bounds.mjs
// therefore measures the same `proc:souvenirShelf` box regardless of save
// state, and the roomAudit drift lock holds for every player.
//
// Pure exports (MINI_SPECS/SHELF/visitedSignature/normalizeVisited/
// readVisited) carry no three.js objects — test/souvenirShelf.test.js
// validates recipes and signatures headlessly; the geometry builders load
// three (importable under node like roomManager.js).

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
// read-only imports of G1-owned modules (ids + the frozen slice contract)
import { VACATION_IDS } from '../data/vacations.js';
import { sliceOf } from '../systems/vacation.js';

// ---------------------------------------------------------------------------
// Shelf dimensions (holder-local meters; y 0 = plank underside — the living
// room's furniture entry lifts the holder to the wall spot). Reviewed audit
// bounds: x ±0.75 · y 0..0.24 · z ±0.085 (see roomAudit.rules.js living).
// ---------------------------------------------------------------------------
export const SHELF = Object.freeze({
  /** plank: width × thickness × depth */
  PLANK: Object.freeze({ W: 1.5, T: 0.035, D: 0.17 }),
  /** backboard: height × thickness (width = plank width) */
  BACK: Object.freeze({ H: 0.24, T: 0.022 }),
  /** first slot's local x + pitch — 9 slots span x −0.6..0.6 */
  SLOT_X0: -0.6,
  SLOT_PITCH: 0.15,
  /** minis stand this far forward of the plank's z center */
  SLOT_Z: 0.01,
  PLANK_COLOR: '#B98A62',
  BACK_COLOR: '#CBA478',
});

/**
 * One distinct mini per destination (FINAL-WAVE recipe): shell, flower jar,
 * skyline token, moon rock, lighthouse, pumpkin, pastry, star jar, toy
 * block. PURE DATA — each spec is `{shape, size, color, at, rot?, scale?}`
 * in mini-local space (y 0 = plank top, x/z centered on the slot; rot in
 * radians, XYZ order). Shapes map to three.js primitives in specGeometry().
 * Every mini stays inside |x|,|z| ≤ 0.065 and y ≤ 0.185 — under the
 * backboard top (0.24) and on the plank (±0.085 deep), preserving the
 * envelope invariant above.
 * @type {Readonly<Record<string, ReadonlyArray<object>>>}
 */
export const MINI_SPECS = Object.freeze({
  // beach — a sun-bleached shell with a tiny pearl
  beach: Object.freeze([
    Object.freeze({ shape: 'sphere', size: Object.freeze([0.048]), color: '#F6D3BD', at: Object.freeze([0, 0.028, 0]), scale: Object.freeze([1, 0.58, 0.85]) }),
    Object.freeze({ shape: 'sphere', size: Object.freeze([0.013]), color: '#FFF4E4', at: Object.freeze([0.028, 0.013, 0.032]) }),
  ]),
  // meadowTrip — a pressed-flower jar (stem + blossom in a pastel pot)
  meadowTrip: Object.freeze([
    Object.freeze({ shape: 'cyl', size: Object.freeze([0.026, 0.03, 0.055]), color: '#DDEEDF', at: Object.freeze([0, 0.0275, 0]) }),
    Object.freeze({ shape: 'cyl', size: Object.freeze([0.004, 0.004, 0.05]), color: '#7FB069', at: Object.freeze([0, 0.08, 0]) }),
    Object.freeze({ shape: 'sphere', size: Object.freeze([0.019]), color: '#F7A8C4', at: Object.freeze([0, 0.112, 0]) }),
    Object.freeze({ shape: 'sphere', size: Object.freeze([0.008]), color: '#FFE28A', at: Object.freeze([0, 0.112, 0.017]) }),
  ]),
  // bigCity — a three-tower skyline token on a sidewalk base
  bigCity: Object.freeze([
    Object.freeze({ shape: 'box', size: Object.freeze([0.105, 0.012, 0.05]), color: '#C9CFDD', at: Object.freeze([0, 0.006, 0]) }),
    Object.freeze({ shape: 'box', size: Object.freeze([0.026, 0.062, 0.026]), color: '#8FA1C0', at: Object.freeze([-0.032, 0.043, 0.004]) }),
    Object.freeze({ shape: 'box', size: Object.freeze([0.026, 0.095, 0.026]), color: '#A7B6D4', at: Object.freeze([0, 0.0595, -0.006]) }),
    Object.freeze({ shape: 'box', size: Object.freeze([0.026, 0.048, 0.026]), color: '#7C8DB0', at: Object.freeze([0.033, 0.036, 0.006]) }),
  ]),
  // space — a faceted moon rock with a crater knob
  space: Object.freeze([
    Object.freeze({ shape: 'ico', size: Object.freeze([0.042]), color: '#C3C9DA', at: Object.freeze([0, 0.036, 0]) }),
    Object.freeze({ shape: 'ico', size: Object.freeze([0.012]), color: '#98A1BA', at: Object.freeze([0.02, 0.06, 0.014]) }),
  ]),
  // harbor — a striped lighthouse with a lit lamp room
  harbor: Object.freeze([
    Object.freeze({ shape: 'cyl', size: Object.freeze([0.02, 0.027, 0.06]), color: '#E86A5E', at: Object.freeze([0, 0.03, 0]) }),
    Object.freeze({ shape: 'cyl', size: Object.freeze([0.016, 0.02, 0.045]), color: '#FFF6E8', at: Object.freeze([0, 0.0825, 0]) }),
    Object.freeze({ shape: 'cyl', size: Object.freeze([0.013, 0.013, 0.018]), color: '#FFE28A', at: Object.freeze([0, 0.114, 0]) }),
    Object.freeze({ shape: 'cone', size: Object.freeze([0.018, 0.026]), color: '#E86A5E', at: Object.freeze([0, 0.136, 0]) }),
  ]),
  // spookGarden — a plump pumpkin with a crooked stem
  spookGarden: Object.freeze([
    Object.freeze({ shape: 'sphere', size: Object.freeze([0.042]), color: '#F0973F', at: Object.freeze([0, 0.033, 0]), scale: Object.freeze([1, 0.78, 1]) }),
    Object.freeze({ shape: 'cyl', size: Object.freeze([0.006, 0.008, 0.022]), color: '#7B9A56', at: Object.freeze([0.004, 0.073, 0]), rot: Object.freeze([0, 0, 0.25]) }),
  ]),
  // bakery — a frosted cupcake with a cherry
  bakery: Object.freeze([
    Object.freeze({ shape: 'cyl', size: Object.freeze([0.03, 0.023, 0.038]), color: '#E8C9A0', at: Object.freeze([0, 0.019, 0]) }),
    Object.freeze({ shape: 'sphere', size: Object.freeze([0.03]), color: '#F6B8D0', at: Object.freeze([0, 0.05, 0]), scale: Object.freeze([1, 0.72, 1]) }),
    Object.freeze({ shape: 'sphere', size: Object.freeze([0.009]), color: '#DE5449', at: Object.freeze([0, 0.078, 0]) }),
  ]),
  // nightSky — a corked star jar with a gold star on the lid
  nightSky: Object.freeze([
    Object.freeze({ shape: 'cyl', size: Object.freeze([0.027, 0.027, 0.062]), color: '#CFE3F7', at: Object.freeze([0, 0.031, 0]) }),
    Object.freeze({ shape: 'cyl', size: Object.freeze([0.029, 0.029, 0.012]), color: '#A9805A', at: Object.freeze([0, 0.068, 0]) }),
    Object.freeze({ shape: 'oct', size: Object.freeze([0.017]), color: '#FFD966', at: Object.freeze([0, 0.089, 0]), scale: Object.freeze([1, 0.8, 1]) }),
  ]),
  // toyRoom — two stacked toy blocks, playfully askew
  toyRoom: Object.freeze([
    Object.freeze({ shape: 'box', size: Object.freeze([0.048, 0.048, 0.048]), color: '#F2C94C', at: Object.freeze([0, 0.024, 0]), rot: Object.freeze([0, 0.26, 0]) }),
    Object.freeze({ shape: 'box', size: Object.freeze([0.036, 0.036, 0.036]), color: '#7FB3E8', at: Object.freeze([0.006, 0.066, 0.004]), rot: Object.freeze([0, -0.35, 0]) }),
  ]),
});

// ---------------------------------------------------------------------------
// visited-map normalization + signature (pure)
// ---------------------------------------------------------------------------

/**
 * Re-normalize any visited-shaped value through the known recipe ids:
 * only `id === true` entries of KNOWN destinations survive. Junk in (null,
 * arrays, `{beach: 1}`, `{atlantis: true}`) → clean map out.
 * @param {*} visited raw or normalized visited map
 * @returns {Record<string, true>}
 */
export function normalizeVisited(visited) {
  /** @type {Record<string, true>} */
  const out = {};
  if (visited == null || typeof visited !== 'object' || Array.isArray(visited)) return out;
  for (const id of VACATION_IDS) {
    if (visited[id] === true && MINI_SPECS[id]) out[id] = true;
  }
  return out;
}

/**
 * Stable rebuild key for a visited map — identical maps (any key order, any
 * junk) produce identical signatures, so the shelf re-merges only on REAL
 * progress changes.
 * @param {*} visited
 * @returns {string} e.g. '' | 'beach' | 'beach,space'
 */
export function visitedSignature(visited) {
  return Object.keys(normalizeVisited(visited)).sort().join(',');
}

/**
 * Read the visited map off a save state via the FROZEN G1 contract
 * `vacation.sliceOf(state).visited`, with a defensive fallback for the
 * mid-wave window where G1's normalized field hasn't landed yet (sliceOf
 * whitelist-strips unknown fields): fall back to the RAW slice field, then
 * to empty. Both paths re-normalize here, so the result is always a clean
 * known-ids→true map.
 * @param {object} state save state (or any `{vacation?}` shape)
 * @returns {Record<string, true>}
 */
export function readVisited(state) {
  const slice = sliceOf(state);
  const raw = state?.vacation;
  const map = slice?.visited
    ?? (raw != null && typeof raw === 'object' ? raw.visited : null);
  return normalizeVisited(map);
}

// ---------------------------------------------------------------------------
// geometry (three.js — merged single-call build)
// ---------------------------------------------------------------------------

/** @param {object} spec MINI_SPECS entry @returns {THREE.BufferGeometry} */
function specGeometry(spec) {
  const s = spec.size;
  switch (spec.shape) {
    case 'box': return new THREE.BoxGeometry(s[0], s[1], s[2]);
    case 'sphere': return new THREE.SphereGeometry(s[0], 10, 8);
    case 'cyl': return new THREE.CylinderGeometry(s[0], s[1], s[2], 10);
    case 'cone': return new THREE.ConeGeometry(s[0], s[1], 10);
    case 'ico': return new THREE.IcosahedronGeometry(s[0], 0);
    case 'oct': return new THREE.OctahedronGeometry(s[0], 0);
    default: throw new Error(`souvenirShelf: unknown primitive shape '${spec.shape}'`);
  }
}

/**
 * Bake one primitive: transform applied, vertex colors filled, attributes
 * normalized to position/normal/color (the decor.js merged-batch pattern —
 * every source must agree for mergeGeometries).
 * @returns {THREE.BufferGeometry}
 */
function bakedPrimitive(source, color, at, rot = [0, 0, 0], scale = [1, 1, 1]) {
  const geo = source.index ? source.toNonIndexed() : source;
  if (geo !== source) source.dispose();
  geo.applyMatrix4(new THREE.Matrix4().compose(
    new THREE.Vector3(...at),
    new THREE.Quaternion().setFromEuler(new THREE.Euler(...rot)),
    new THREE.Vector3(...scale)
  ));
  if (!geo.getAttribute('normal')) geo.computeVertexNormals();
  const count = geo.getAttribute('position').count;
  const c = new THREE.Color(color);
  const colors = new Float32Array(count * 3);
  for (let i = 0; i < count; i += 1) {
    colors[i * 3] = c.r;
    colors[i * 3 + 1] = c.g;
    colors[i * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  for (const name of Object.keys(geo.attributes)) {
    if (name !== 'position' && name !== 'normal' && name !== 'color') geo.deleteAttribute(name);
  }
  return geo;
}

/**
 * Merge plank + backboard + one mini per visited destination into ONE
 * vertex-colored BufferGeometry (holder-local space, y 0 = plank underside).
 * The caller owns the returned geometry (dispose on rebuild).
 * @param {*} visited visited map (normalized here — junk-safe)
 * @returns {THREE.BufferGeometry}
 */
export function buildShelfGeometry(visited) {
  const { PLANK, BACK, SLOT_X0, SLOT_PITCH, SLOT_Z } = SHELF;
  const map = normalizeVisited(visited);
  const geos = [
    bakedPrimitive(
      new THREE.BoxGeometry(PLANK.W, PLANK.T, PLANK.D),
      SHELF.PLANK_COLOR, [0, PLANK.T / 2, 0]
    ),
    bakedPrimitive(
      new THREE.BoxGeometry(PLANK.W, BACK.H, BACK.T),
      SHELF.BACK_COLOR, [0, BACK.H / 2, -PLANK.D / 2 + BACK.T / 2]
    ),
  ];
  for (let i = 0; i < VACATION_IDS.length; i += 1) {
    const destId = VACATION_IDS[i];
    if (!map[destId]) continue; // not visited (or unknown — never built)
    const slotX = SLOT_X0 + i * SLOT_PITCH;
    for (const spec of MINI_SPECS[destId] ?? []) {
      geos.push(bakedPrimitive(
        specGeometry(spec),
        spec.color,
        [slotX + spec.at[0], PLANK.T + spec.at[1], SLOT_Z + spec.at[2]],
        spec.rot ?? [0, 0, 0],
        spec.scale ?? [1, 1, 1]
      ));
    }
  }
  const merged = mergeGeometries(geos, false);
  for (const geo of geos) geo.dispose();
  if (!merged) throw new Error('souvenirShelf: geometry merge failed');
  return merged;
}

/**
 * Live shelf controller — ONE mesh, ONE material, rebuild-on-signature.
 * roomManager mounts `group` inside the `proc:souvenirShelf` furniture
 * holder, calls `refresh()` on store 'change' events and `dispose()` when
 * the home scene tears down.
 * @param {() => *} getVisited reads the CURRENT visited map (any shape —
 *   normalized internally)
 * @returns {{group: THREE.Group, refresh: () => boolean,
 *   dispose: () => void, signature: () => string|null}}
 */
export function createSouvenirShelf(getVisited) {
  const group = new THREE.Group();
  group.name = 'souvenir-shelf';
  const material = new THREE.MeshStandardMaterial({
    vertexColors: true,
    roughness: 0.82,
    metalness: 0,
  });
  /** @type {THREE.Mesh|null} */
  let mesh = null;
  /** @type {string|null} */
  let signature = null;

  const removeMesh = () => {
    if (!mesh) return;
    group.remove(mesh);
    mesh.geometry.dispose(); // material is shared across rebuilds
    mesh = null;
  };

  /** @returns {boolean} true when the shelf actually re-merged */
  const refresh = () => {
    const visited = getVisited?.();
    const sig = visitedSignature(visited);
    if (sig === signature) return false; // rebuild ONLY on signature change
    signature = sig;
    removeMesh();
    mesh = new THREE.Mesh(buildShelfGeometry(visited), material);
    mesh.name = 'souvenir-shelf-merged';
    mesh.castShadow = false; // wall mount high on the back wall (noShadow)
    mesh.receiveShadow = true;
    group.add(mesh);
    return true;
  };

  refresh(); // build the initial state synchronously

  return {
    group,
    refresh,
    dispose() {
      removeMesh();
      material.dispose();
      signature = null;
    },
    signature: () => signature,
  };
}
