// V6/F2 — Transient ambient visitors (PLAN6 Wave F / F2): the garden bird.
// This is the three.js MOUNT side only — the schedule (clock-hashed, no save
// writes), the room/band/weather gate and the full flight/hop/peck pose
// sampler are all pure functions in src/home/ambientLife.data.js (VISITOR /
// visitorCycleSpec / activeVisit / visitorPose), tested headlessly in
// test/ambientVisitors.test.js. node tests never import this file.
//
// Contract (homeScene.js owns the lifecycle via marked V6/F2 blocks):
//   const visitors = createAmbientVisitors({ rm });  // after createRoomManager
//   visitors.setConditions(band, weather);           // inside applyAmbienceNow()
//   visitors.update(dt);                             // beside ambient.update(dt)
//   visitors.getWatchable();                         // watch-loop candidate|null
//   visitors.dispose();                              // homeScene dispose()
//
// Behavior:
// - Polls activeVisit(room, band, weather, now()) every frame (cheap: two
//   hash calls worst-case) and mounts the itch pretty-park bird GLB into the
//   garden room group only while a visit is live. The GLB is already in the
//   asset cache (rooms/garden.js places a STATIC bench bird from the same
//   key), so getModel() is a synchronous clone — no fetch on the hot path.
// - The visit itself is wall-clock stateless: hidden tabs / ?now= pins jump
//   straight to the right phase (or to "no bird") on the next update tick.
//   The RAF loop pausing while hidden is the visibility cleanup — nothing
//   renders, and the first resumed tick unmounts an expired visit.
// - Room switch mid-visit despawns IMMEDIATELY via rm 'roomChanged' (not
//   just the next poll) so the pan never shows a stray bird; the clone
//   shares the cache master's geometry/materials (assets.js F5/E14 caveat),
//   so unmount removes the group and disposes NOTHING.
// - No-op under prefersReducedMotion() (ui/ui.js predicate) — a bird
//   swooping across the garden is exactly the motion the OS setting asks us
//   to skip. The static bench bird (E4) still provides the decorative beat.
// - Budget: the bird GLB is a single mesh → 1 transient draw call, proven
//   live by getDebugStats().drawCalls against VISITOR.MAX_DRAW_CALLS (≤2).

import * as THREE from 'three';
import { prefersReducedMotion } from '../ui/ui.js';
import { getModel } from '../core/assets.js';
import { now } from '../core/clock.js';
import { activeVisit, visitorPose, VISITOR } from './ambientLife.data.js';

/** Asset key of the visitor model (same songbird E4 perched on the bench). */
const BIRD_KEY = 'pretty-park/bird';
/** Matches the static bench bird's scale (rooms/garden.js decor entry). */
const BIRD_SCALE = 0.45;
/**
 * Model-forward correction: visitorPose yaws assume the bird faces +Z; the
 * pretty-park GLB's beak points toward -Z, so spin the clone half a turn.
 */
const BIRD_YAW_OFFSET = Math.PI;

/** Shared no-op raycast so the visitor can never swallow a tap:* raycast. */
const NO_RAYCAST = () => {};

/**
 * Transient-visitor manager for the home scene. Reduced motion → inert stub
 * with the same API (nothing mounts, all methods no-op).
 *
 * @param {{rm: {
 *   activeRoom: () => string,
 *   getRoomGroup: (roomId: string) => THREE.Group|null,
 *   getAnchorLocal?: (name: string, roomId?: string) => THREE.Vector3|null,
 *   on: (event: string, cb: Function) => () => void,
 * }}} deps
 */
export function createAmbientVisitors({ rm }) {
  const reducedMotion = prefersReducedMotion();

  let band = null;
  let weather = null;
  let disposed = false;

  /** @type {THREE.Group|null} the mounted bird clone (garden room-local) */
  let bird = null;
  /** cycle index of the mounted visit (remount guard across visits) */
  let mountedCycle = -1;
  /** perch anchor, room-local (resolved once per mount) */
  const perch = [0, 0, 0];
  /** last sampled phase ('in'|'stay'|'out'|null) — debug/watch gating */
  let phase = null;
  /** meshes in the mounted clone = transient draw calls (budget proof) */
  let drawCalls = 0;

  // watch-loop candidate (single cached entry — no per-call allocation)
  const watchPos = new THREE.Vector3();
  const watchable = {
    id: 'visitor:bird',
    pos: watchPos,
    enterRadius: VISITOR.WATCH_ENTER_RADIUS,
    exitRadius: VISITOR.WATCH_EXIT_RADIUS,
  };

  function unmount() {
    if (!bird) return;
    bird.parent?.remove(bird);
    // Clone geometry/materials are SHARED with the permanent asset cache —
    // disposing them would evict the master's GPU buffers (assets.js F5/E14
    // caveat, same rule roomManager.disposeIfOwned follows). Drop refs only.
    bird = null;
    mountedCycle = -1;
    phase = null;
    drawCalls = 0;
  }

  /** @param {{cycle: number}} visit */
  function mount(visit) {
    const roomGroup = rm.getRoomGroup?.(VISITOR.ROOM);
    const local = rm.getAnchorLocal?.(VISITOR.ANCHOR, VISITOR.ROOM);
    if (!roomGroup || !local) return;
    perch[0] = local.x;
    perch[1] = local.y;
    perch[2] = local.z;
    bird = getModel(BIRD_KEY);
    bird.name = 'ambient-visitor-bird';
    bird.scale.setScalar(BIRD_SCALE);
    drawCalls = 0;
    bird.traverse((obj) => {
      obj.raycast = NO_RAYCAST;
      if (obj.isMesh) {
        obj.castShadow = false; // transient decor: skip the shadow pass
        drawCalls += 1;
      }
    });
    roomGroup.add(bird);
    mountedCycle = visit.cycle;
  }

  // Room switch mid-visit → despawn immediately (don't wait for the poll):
  // the room pan must never drag a stray bird across the apartment.
  const offRoomChanged = reducedMotion
    ? null
    : rm.on?.('roomChanged', ({ roomId }) => {
      if (roomId !== VISITOR.ROOM) unmount();
    }) ?? null;

  const api = {
    /**
     * Band/weather gate swap — homeScene calls this from applyAmbienceNow()
     * (marked V6/F2 hook), same cadence as ambientLife.setConditions.
     * @param {'night'|'dawn'|'day'|'dusk'} nextBand
     * @param {'clear'|'cloudy'|'rain'} nextWeather
     */
    setConditions(nextBand, nextWeather) {
      if (disposed || reducedMotion) return;
      band = nextBand;
      weather = nextWeather;
    },

    /** Per-frame tick — rides homeScene.update(dt), pausing with the RAF loop. */
    update() {
      if (disposed || reducedMotion) return;
      const ms = now();
      const visit = activeVisit(rm.activeRoom?.(), band, weather, ms);
      if (!visit) {
        unmount();
        return;
      }
      if (!bird || mountedCycle !== visit.cycle) {
        unmount();
        mount(visit);
        if (!bird) return;
      }
      const pose = visitorPose(visit, ms, perch);
      phase = pose.phase;
      bird.position.set(pose.position[0], pose.position[1], pose.position[2]);
      bird.rotation.set(pose.pitch, pose.yaw + BIRD_YAW_OFFSET, 0);
    },

    /**
     * The bird as a watch-loop candidate for the F2 "Gooby watches" logic
     * (world position, cached vector — no per-call allocation), or null
     * while no bird is perched. Only the 'stay' phase is watchable: gaze
     * chasing a bird in fast flight looks frantic, not curious.
     * @returns {{id: string, pos: THREE.Vector3, enterRadius: number,
     *   exitRadius: number}|null}
     */
    getWatchable() {
      if (!bird || phase !== 'stay') return null;
      bird.getWorldPosition(watchPos);
      return watchable;
    },

    /**
     * Live budget/behavior proof (PLAN6 F2: the bird adds ≤2 transient draw
     * calls — VISITOR.MAX_DRAW_CALLS).
     * @returns {{reducedMotion: boolean, mounted: boolean, cycle: number,
     *   phase: string|null, drawCalls: number, withinBudget: boolean}}
     */
    getDebugStats() {
      return {
        reducedMotion,
        mounted: !!bird,
        cycle: mountedCycle,
        phase,
        drawCalls,
        withinBudget: drawCalls <= VISITOR.MAX_DRAW_CALLS,
      };
    },

    /** Full teardown: despawn + release the roomChanged subscription. */
    dispose() {
      if (disposed) return;
      disposed = true;
      offRoomChanged?.();
      unmount();
    },
  };

  return api;
}
