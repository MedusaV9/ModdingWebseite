// AI traffic (§G G7, §C6.1 #1): 6–10 Kenney car-kit cars (taxi/van/police/
// delivery/suv) looping fixed lane paths derived from the layout's closed
// tile cycles, with forgiving 70%-scaled AABB collision vs the player
// (DRIVE_TUNING.TRAFFIC_HITBOX_SCALE). Traffic never chases or reacts — it
// just keeps driving its loop (cozy, §A pillar 4).

import * as THREE from 'three';
import { DRIVE_TUNING } from '../data/constants.js';
import {
  tileToWorld,
  laneOffsetPolyline,
  polylineLength,
  pointAtLength,
} from './cityBuilder.js';
import { ensureWheels } from './carController.js';

const T = DRIVE_TUNING;

/** Traffic model rotation (types cycle §C6.1's list). */
const CAR_TYPES = ['taxi', 'van', 'police', 'delivery', 'suv'];

/** Authored half-extents (units) of the widest traffic bodies (car-kit). */
const CAR_HALF_W = 0.75;
const CAR_HALF_L = 1.5;

/** GLB keys the traffic needs preloaded. */
export const TRAFFIC_ASSET_KEYS = Object.freeze([
  ...CAR_TYPES.map((id) => `car-kit/${id}`),
  'car-kit/wheel-default',
]);

// ── V4/GAME-POLISH-5: near-miss detection (cosmetic juice only) ─────────────
// A "near miss" = the player's FULL box swept through a traffic car's
// margin-expanded FULL box at speed and left it again without checkHit ever
// firing. Purely additive: collision/crash scoring paths are untouched —
// callers use the fire signal for sfx/sparkles/banner only.
/** Frozen near-miss tuning (V4/GAME-POLISH-5, module-local per §E0.1-3). */
export const NEAR_MISS = Object.freeze({
  /** Margin (m) around the FULL car box that counts as "close". */
  MARGIN_M: 1.05,
  /** Player must be at/above this speed (m/s) for the whole pass. */
  MIN_SPEED_MS: 7.5,
  /** Per-car re-fire cooldown (s) so one slalom can't farm a single car. */
  COOLDOWN_SEC: 1.5,
});

/**
 * Pure per-car near-miss tracker step (unit-tested headlessly). Call once
 * per frame per car; returns true exactly when a clean fast pass COMPLETES
 * (the overlap window ends with no collision and no slow frame inside it).
 * @param {{inside: boolean, dirty: boolean}} state per-car tracker (mutated)
 * @param {boolean} overlapped player box overlaps the margin-expanded box
 * @param {boolean} collided a real checkHit fired on this car (cooldown up)
 * @param {boolean} speedOk player speed ≥ NEAR_MISS.MIN_SPEED_MS this frame
 * @returns {boolean} fire the near-miss juice now
 */
export function stepNearMiss(state, overlapped, collided, speedOk) {
  if (collided) {
    // a touch anywhere voids the pass (and any window already in progress)
    state.inside = false;
    state.dirty = false;
    return false;
  }
  if (overlapped) {
    if (!state.inside) {
      state.inside = true;
      state.dirty = !speedOk;
    } else if (!speedOk) {
      state.dirty = true;
    }
    return false;
  }
  const fire = state.inside && !state.dirty;
  state.inside = false;
  state.dirty = false;
  return fire;
}
// ── end V4/GAME-POLISH-5 ────────────────────────────────────────────────────

/**
 * V4/FIX-3D: minimal positional separation after a checkHit — the forgiving
 * 70% hit test fires while the FULL car bodies already interpenetrate, so
 * push the player's position out of the hit car's full box along the
 * smaller-penetration axis. Positional resolve only; crash/scoring beats in
 * the callers are untouched.
 * @param {import('three').Vector3} playerPos live player position (mutated)
 * @param {{minX: number, maxX: number, minZ: number, maxZ: number}} playerAabb
 *   FULL-size player box (car.aabb() with no scale)
 * @param {{x: number, z: number, hx: number, hz: number}} hit checkHit result
 */
export function separateFromHit(playerPos, playerAabb, hit) {
  const overlapX = Math.min(playerAabb.maxX, hit.x + hit.hx)
    - Math.max(playerAabb.minX, hit.x - hit.hx);
  const overlapZ = Math.min(playerAabb.maxZ, hit.z + hit.hz)
    - Math.max(playerAabb.minZ, hit.z - hit.hz);
  if (overlapX <= 0 || overlapZ <= 0) return; // bodies already clear
  const pad = 0.05; // small daylight so the boxes end just touching
  if (overlapX <= overlapZ) {
    playerPos.x += (playerPos.x >= hit.x ? 1 : -1) * (overlapX + pad);
  } else {
    playerPos.z += (playerPos.z >= hit.z ? 1 : -1) * (overlapZ + pad);
  }
}

/**
 * @param {{
 *   scene: import('three').Scene,
 *   assets: {getModel: (key: string) => import('three').Object3D},
 *   layout: import('./cityBuilder.js').CityLayout,
 *   rng: () => number,
 * }} deps rng: the framework-seeded stream (start offsets only — lanes are fixed)
 * @returns {{
 *   update: (dt: number) => void,
 *   checkHit: (playerAabb: {minX: number, maxX: number, minZ: number, maxZ: number}) =>
 *     ({x: number, z: number, hx: number, hz: number}|null),
 *   dispose: () => void,
 * }}
 */
export function createTraffic({ scene, assets, layout, rng }) {
  const group = new THREE.Group();
  group.name = 'traffic';
  scene.add(group);

  // closed lane polylines (right-hand offset per loop travel direction)
  const lanes = layout.trafficLoops.map((tiles) => {
    const center = tiles.map(([r, c]) => tileToWorld(r, c));
    const pts = laneOffsetPolyline(center, T.LANE_OFFSET_M, true);
    return { pts, length: polylineLength(pts, true) };
  });

  /** @type {Array<{model: THREE.Object3D, wheels: THREE.Object3D[], lane: {pts: object[], length: number}, s: number, hitCooldown: number}>} */
  const cars = [];
  for (let i = 0; i < T.TRAFFIC_COUNT; i++) {
    const lane = lanes[i % lanes.length];
    const type = CAR_TYPES[i % CAR_TYPES.length];
    const model = assets.getModel(`car-kit/${type}`);
    model.scale.setScalar(T.CAR_SCALE);
    const wheels = ensureWheels(model, assets);
    group.add(model);
    cars.push({
      model,
      wheels,
      lane,
      // spread cars around their loop (rng jitter keeps rounds varied)
      s: ((Math.floor(i / lanes.length) + 1) / (Math.ceil(T.TRAFFIC_COUNT / lanes.length) + 1) + rng() * 0.1) * lane.length,
      hitCooldown: 0,
      // V4/GAME-POLISH-5: per-car near-miss tracker + re-fire cooldown
      near: { inside: false, dirty: false },
      nearCooldown: 0,
    });
  }

  function place(car) {
    const p = pointAtLength(car.lane.pts, car.s, true);
    car.model.position.set(p.x, T.ROAD_Y, p.z);
    car.model.rotation.y = Math.atan2(p.dx, p.dz);
  }
  for (const car of cars) place(car);

  const hw = CAR_HALF_W * T.CAR_SCALE;
  const hl = CAR_HALF_L * T.CAR_SCALE;

  return {
    /** @param {number} dt */
    update(dt) {
      const wheelOmega = (T.TRAFFIC_SPEED / T.CAR_SCALE / 0.3) * dt;
      for (const car of cars) {
        car.s = (car.s + T.TRAFFIC_SPEED * dt) % car.lane.length;
        car.hitCooldown = Math.max(0, car.hitCooldown - dt);
        car.nearCooldown = Math.max(0, car.nearCooldown - dt); // V4/GAME-POLISH-5
        place(car);
        for (const w of car.wheels) w.rotation.x += wheelOmega;
      }
    },

    /**
     * V4/GAME-POLISH-5: cosmetic near-miss probe — call once per frame with
     * the FULL player box + current speed. Returns the passed car's position
     * when a clean fast pass just completed (see stepNearMiss), else null.
     * Never touches the crash path: checkHit's own cooldown doubles as the
     * "this pass touched" signal.
     * @param {{minX: number, maxX: number, minZ: number, maxZ: number}} playerAabb
     * @param {number} speed player speed (m/s)
     */
    checkNearMiss(playerAabb, speed) {
      const speedOk = speed >= NEAR_MISS.MIN_SPEED_MS;
      let firedAt = null;
      for (const car of cars) {
        const p = car.model.position;
        const rotated = Math.abs(Math.sin(car.model.rotation.y)) > 0.5;
        const hx = (rotated ? hl : hw) + NEAR_MISS.MARGIN_M;
        const hz = (rotated ? hw : hl) + NEAR_MISS.MARGIN_M;
        const overlapped =
          playerAabb.minX < p.x + hx && playerAabb.maxX > p.x - hx &&
          playerAabb.minZ < p.z + hz && playerAabb.maxZ > p.z - hz;
        const fire = stepNearMiss(car.near, overlapped, car.hitCooldown > 0, speedOk);
        if (fire && car.nearCooldown <= 0 && !firedAt) {
          car.nearCooldown = NEAR_MISS.COOLDOWN_SEC;
          firedAt = { x: p.x, z: p.z };
        }
      }
      return firedAt;
    },

    /**
     * Forgiving collision (§C6.1): both boxes pre-scaled to 70%. Returns the
     * hit car's position + FULL-size rotation-aware half extents (V4/FIX-3D:
     * the caller separates the bodies so they never interpenetrate on the
     * crash frame) or null. A short per-car cooldown avoids double-counting
     * one bump.
     * @param {{minX: number, maxX: number, minZ: number, maxZ: number}} playerAabb
     */
    checkHit(playerAabb) {
      for (const car of cars) {
        if (car.hitCooldown > 0) continue;
        const p = car.model.position;
        const rotated = Math.abs(Math.sin(car.model.rotation.y)) > 0.5;
        const fx = rotated ? hl : hw;
        const fz = rotated ? hw : hl;
        const hx = fx * T.TRAFFIC_HITBOX_SCALE;
        const hz = fz * T.TRAFFIC_HITBOX_SCALE;
        if (
          playerAabb.minX < p.x + hx && playerAabb.maxX > p.x - hx &&
          playerAabb.minZ < p.z + hz && playerAabb.maxZ > p.z - hz
        ) {
          car.hitCooldown = 2.5;
          return { x: p.x, z: p.z, hx: fx, hz: fz };
        }
      }
      return null;
    },

    dispose() {
      scene.remove(group);
    },
  };
}
