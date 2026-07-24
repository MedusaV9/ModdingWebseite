// V6/F4 — Funkelpark Riesenrad (PLAN6 Wave F/F4): the calm anti-coaster.
// Fully procedural build — rim/spokes/hub/A-frame legs/gondolas from three.js
// primitives + instancing, NO new assets, NO cover, NO economy calls, NO save
// fields. Mounted by park/parkScene.js at E1's reserved `ferrisWheel` anchor
// (kind/key stay 'reserved'/null — test/parkLayout.test.js pins them and the
// wheel needs no GLB key), ambient ~1 rpm scenery while in the plaza, and a
// ~45 s REAL-TIME gentle ride via startWheelRide(ctx).
//
// The file is layered like A3's ambientLife split, but in ONE module (the F4
// owned-file list has no .logic sibling): everything above the "VIEW" banner
// is PURE (plain math/data — no DOM, and three.js only appears below), so
// test/ferrisWheel.test.js drives the classic-bug invariant headlessly:
// gondolaTransform(theta, i) counter-rotates the cabins so they stay UPRIGHT
// for every wheel angle and never swing through a spoke (spokes are offset
// half a bay from the gondola pivots; the cabin's swept disc provably clears
// them — closed form AND sampled point-to-segment distance).
//
// Ride notes (PLAN6 F4 acceptance):
// - camera tween via gfx/tween.js, snapshot + `finally`-style restore (E2's
//   lease pattern) — the plaza pan resumes on the exact pose it left.
// - reduced motion = static apex shot with caption (no orbit, no spin).
// - tap-to-end-early after EARLY_TAP_SEC (calm ride — the wheel gently rolls
//   on to the exit instead of jump-cutting).
// - HUD camera reality (documented, per plan): ui/hud.js hides the whole HUD
//   outside the 'home' scene and ui/photoMode.js enter() refuses when
//   sceneManager.currentId() !== 'home' (§C12.2) — so the HUD camera button
//   cannot mount in the park at all. The ride therefore does NOT block any
//   camera; instead it mirrors E2's coasterRide souvenir: one automatic
//   apex captureFrame → photo gallery (the "photo spot for free").

import * as THREE from 'three';
import { t, getLang } from '../data/strings.js';
import { EN as PARK_EN, DE as PARK_DE } from '../data/strings/v6-park.js';
import { tween, easings } from '../gfx/tween.js';
import { now } from '../core/clock.js';
import { mirrorSlice } from '../systems/gallery.logic.js';
import { bandAt } from '../systems/dayNight.js'; // V6.1/G3 (B8): night apex line

// ═══════════════════════════════════════════════════════════════════════════
// PURE MODEL (no three.js/DOM below this banner until "VIEW") — everything
// here is imported headlessly by test/ferrisWheel.test.js.
// ═══════════════════════════════════════════════════════════════════════════

const TAU = Math.PI * 2;

/** §E0.1-2: the binding wheel geometry numbers (meters/radians), frozen. */
export const WHEEL = Object.freeze({
  /** rim radius (m) — apex = HUB_HEIGHT + RADIUS ≈ 9.2 m over the plaza */
  RADIUS: 4.0,
  /** axle height above ground (m) */
  HUB_HEIGHT: 5.2,
  /** gondola count (evenly spaced; spokes sit HALF A BAY off the pivots) */
  GONDOLAS: 8,
  /** pivot → cabin-center hang distance (m) */
  GONDOLA_DROP: 0.72,
  /** cabin body clearance radius (m) — the swept-disc collision proxy */
  GONDOLA_R: 0.45,
  /** spoke cylinder radius (m) */
  SPOKE_R: 0.06,
  /** hub cap radius (m) — the swept disc must clear this too */
  HUB_R: 0.42,
  /** rim tube minor radius (m) */
  RIM_TUBE_R: 0.09,
  /** the two rims / spoke fans sit at z = ±RIM_Z (cabins at z = 0) */
  RIM_Z: 0.5,
  /** ambient plaza rotation (~1 rpm — parkDressing-like scenery) */
  AMBIENT_RPM: 1,
});

/** Alternating pastel cabin colors (i % 4) + their deeper roof partners. */
export const GONDOLA_COLORS = Object.freeze(['#F9C0D0', '#BCE5D2', '#FFE2A9', '#C7BBEF']);
export const GONDOLA_ROOFS = Object.freeze(['#E2849E', '#7FC4A8', '#EFBF6F', '#9D8BDD']);

/** §E0.1-2: the binding ride pacing numbers (seconds/rpm/radians), frozen. */
export const WHEEL_RIDE = Object.freeze({
  /** align crawl toward the nearest boarding angle (≤ π/N → ≤ ~0.9 s) */
  ALIGN_RATE: 0.45,
  /** Gooby's dash-to-platform speed during align/board lead-in (m/s) */
  DASH_SPEED: 6,
  /** boarding hop window (s) */
  BOARD_SEC: 3,
  /** ride revolution speed — one full turn = 40 s (calm) */
  RIDE_RPM: 1.5,
  /** spin-up seconds to full ride speed */
  SPIN_UP_SEC: 2,
  /** ease-out window (radians of travel left) before the stop */
  EASE_OUT_ANG: 0.45,
  /** minimum omega inside the ease-out (rad/s — never stalls short) */
  EASE_MIN_OMEGA: 0.12,
  /** travel angle of the apex beat (half a revolution) */
  APEX_AT: Math.PI,
  /** tap-to-end-early unlocks this many seconds into the ride phase */
  EARLY_TAP_SEC: 10,
  /** the graceful early-return revolution speed (still smooth) */
  RETURN_RPM: 3.2,
  /** disembark hop window (s) */
  DISEMBARK_SEC: 2,
  /** reduced motion: static apex shot dwell before auto-finish (s) */
  RM_HOLD_SEC: 7,
  /** hard force-finish (mirrors systems/cutscene.js watchdog semantics) */
  WATCHDOG_SEC: 120,
});

/** Gooby scale seated in a gondola (park-toy scale — E2's 0.62 precedent). */
export const RIDER_SCALE = 0.62;

/**
 * THE classic-bug invariant, pure: where gondola `i` sits when the wheel has
 * rotated by `theta`, in the STATIC wheel plane (x across, y up, origin at
 * the axle). The rim carries the pivot by `rimRot = theta`; the cabin
 * counter-rotates by `cabinRot = -theta` so its world rotation stays IDENTITY
 * (upright) — cabins hang straight down from their pivots forever.
 * @param {number} theta wheel angle (radians)
 * @param {number} i gondola index 0..n-1
 * @param {number} [n] gondola count
 * @returns {{angle: number, px: number, py: number, cx: number, cy: number,
 *   rimRot: number, cabinRot: number}} pivot (px,py) + cabin center (cx,cy)
 */
export function gondolaTransform(theta, i, n = WHEEL.GONDOLAS) {
  const angle = theta + (i * TAU) / n;
  const px = Math.cos(angle) * WHEEL.RADIUS;
  const py = Math.sin(angle) * WHEEL.RADIUS;
  return {
    angle,
    px,
    py,
    cx: px,
    cy: py - WHEEL.GONDOLA_DROP,
    rimRot: theta,
    cabinRot: -theta,
  };
}

/**
 * Spoke center-line angles at wheel angle `theta` — spokes are deliberately
 * offset HALF A BAY (π/n) from the gondola pivots, so the hanging cabins live
 * in the middle of a spoke-free wedge.
 * @param {number} theta @param {number} [n]
 * @returns {number[]} n angles (radians)
 */
export function spokeAngles(theta, n = WHEEL.GONDOLAS) {
  const out = [];
  for (let k = 0; k < n; k++) out.push(theta + Math.PI / n + (k * TAU) / n);
  return out;
}

/** Distance from point (px,py) to the segment (0,0)→(qx,qy) (pure helper). */
function pointToSpokeDist(px, py, qx, qy) {
  const len2 = qx * qx + qy * qy;
  const u = len2 === 0 ? 0 : Math.max(0, Math.min(1, (px * qx + py * qy) / len2));
  return Math.hypot(px - u * qx, py - u * qy);
}

/**
 * Clearance (m) between gondola `i`'s cabin disc and the NEAREST spoke
 * center-line at wheel angle `theta` (already minus both radii — must stay
 * > 0 for every theta; test/ferrisWheel.test.js sweeps it AND pins the
 * closed form R·sin(π/n) > DROP + GONDOLA_R + SPOKE_R).
 * @param {number} theta @param {number} i @param {number} [n]
 * @returns {number}
 */
export function spokeClearance(theta, i, n = WHEEL.GONDOLAS) {
  const g = gondolaTransform(theta, i, n);
  let best = Infinity;
  for (const a of spokeAngles(theta, n)) {
    const qx = Math.cos(a) * WHEEL.RADIUS;
    const qy = Math.sin(a) * WHEEL.RADIUS;
    best = Math.min(best, pointToSpokeDist(g.cx, g.cy, qx, qy));
  }
  return best - WHEEL.GONDOLA_R - WHEEL.SPOKE_R;
}

/**
 * The draw-batch ledger table (A3's roomBatchCount pattern): the view builds
 * EXACTLY one InstancedMesh/Mesh per row, so the mounted wheel costs
 * WHEEL_BATCHES.length draw calls — the pure ≤6 budget proof.
 */
export const WHEEL_BATCHES = Object.freeze([
  Object.freeze({ id: 'rims', geometry: 'torus', instances: 2, rotor: true }),
  Object.freeze({ id: 'spokes', geometry: 'cylinder', instances: WHEEL.GONDOLAS * 2, rotor: true }),
  Object.freeze({ id: 'structure', geometry: 'cylinder', instances: 8, rotor: false }),
  Object.freeze({ id: 'cabins', geometry: 'capsule', instances: WHEEL.GONDOLAS, rotor: false }),
  Object.freeze({ id: 'roofs', geometry: 'cone', instances: WHEEL.GONDOLAS, rotor: false }),
  Object.freeze({ id: 'platform', geometry: 'box', instances: 1, rotor: false }),
]);

/** Draw calls the mounted wheel adds to the park hub (≤6 — PLAN6 F4). */
export function wheelDrawCalls() {
  return WHEEL_BATCHES.length;
}

/**
 * Disposal ledger (A3's ambientLife.data.js createDisposalLedger semantics):
 * the mount side tracks every geometry/material it creates and the leak test
 * proves disposeAll() drains it.
 * @returns {{track: <T>(res: T, kind?: string) => T, disposeAll: () => number,
 *   outstanding: () => number, byKind: () => Record<string, number>}}
 */
export function createWheelLedger() {
  /** @type {Array<{res: {dispose?: Function}, kind: string}>} */
  let entries = [];
  return {
    track(res, kind = 'resource') {
      entries.push({ res, kind });
      return res;
    },
    disposeAll() {
      const n = entries.length;
      for (const { res } of entries) {
        try {
          res.dispose?.();
        } catch (err) {
          console.error('[ferrisWheel] dispose error:', err);
        }
      }
      entries = [];
      return n;
    },
    outstanding() {
      return entries.length;
    },
    byKind() {
      /** @type {Record<string, number>} */
      const out = {};
      for (const { kind } of entries) out[kind] = (out[kind] ?? 0) + 1;
      return out;
    },
  };
}

/** Wrap an angle into (−π, π]. */
function wrapPi(a) {
  let x = a % TAU;
  if (x <= -Math.PI) x += TAU;
  if (x > Math.PI) x -= TAU;
  return x;
}

/** The wheel-plane angle that puts a pivot at the very bottom. */
const BOTTOM_ANGLE = -Math.PI / 2;

/**
 * Create the PURE ride state (deterministic, dt-driven — no rng, no clock).
 * Boards the gondola NEAREST the bottom, so the align crawl is ≤ π/n rad.
 * @param {{reducedMotion?: boolean, theta0?: number}} [opts]
 */
export function createWheelRide({ reducedMotion = false, theta0 = 0 } = {}) {
  const n = WHEEL.GONDOLAS;
  // nearest gondola to the boarding spot + the SHORTEST signed align delta
  let boardIndex = 0;
  let bestAbs = Infinity;
  let alignDelta = 0;
  for (let i = 0; i < n; i++) {
    const d = wrapPi(BOTTOM_ANGLE - (theta0 + (i * TAU) / n));
    if (Math.abs(d) < bestAbs) {
      bestAbs = Math.abs(d);
      boardIndex = i;
      alignDelta = d;
    }
  }
  if (reducedMotion) {
    // static apex shot: snap the boarded gondola straight to the top
    const apexTheta = theta0 + wrapPi(Math.PI / 2 - (theta0 + (boardIndex * TAU) / n));
    return {
      reducedMotion: true,
      phase: 'rmHold',
      boardIndex,
      theta: apexTheta,
      t: 0,
      totalT: 0,
      rideT: 0,
      rideAngle: WHEEL_RIDE.APEX_AT,
      started: false,
      apexFired: false,
      hintFired: false,
      returned: false,
      done: false,
    };
  }
  return {
    reducedMotion: false,
    phase: 'align',
    boardIndex,
    theta: theta0,
    alignLeft: alignDelta,
    t: 0,
    totalT: 0,
    rideT: 0,
    rideAngle: 0,
    started: false,
    apexFired: false,
    hintFired: false,
    returned: false,
    done: false,
  };
}

/**
 * Advance the pure ride simulation. Events (fired once, in order):
 * board → depart → apex → hintReady → [returnStarted] → arrived → done.
 * @param {ReturnType<typeof createWheelRide>} ride
 * @param {number} dt seconds
 * @param {{tapped?: boolean}} [input] a tap consumed THIS step
 * @returns {Array<{type: string}>}
 */
export function stepWheelRide(ride, dt, input = {}) {
  /** @type {Array<{type: string}>} */
  const events = [];
  if (ride.done) return events;
  ride.t += dt;
  ride.totalT += dt;

  const finishNow = () => {
    if (!ride.done) {
      ride.done = true;
      ride.phase = 'done';
      events.push({ type: 'done' });
    }
  };

  // watchdog: the ride can NEVER trap the player (risk-row-5 discipline)
  if (ride.totalT > WHEEL_RIDE.WATCHDOG_SEC) {
    events.push({ type: 'arrived' });
    finishNow();
    return events;
  }

  if (ride.phase === 'rmHold') {
    if (!ride.started) {
      ride.started = true;
      events.push({ type: 'board' }, { type: 'apex' });
      ride.apexFired = true;
    }
    if (input.tapped || ride.t >= WHEEL_RIDE.RM_HOLD_SEC) {
      events.push({ type: 'arrived' });
      finishNow();
    }
    return events;
  }

  if (ride.phase === 'align') {
    const step = WHEEL_RIDE.ALIGN_RATE * dt * Math.sign(ride.alignLeft || 1);
    if (Math.abs(step) >= Math.abs(ride.alignLeft)) {
      ride.theta += ride.alignLeft;
      ride.alignLeft = 0;
      ride.phase = 'board';
      ride.t = 0;
      events.push({ type: 'board' });
    } else {
      ride.theta += step;
      ride.alignLeft -= step;
    }
    return events;
  }

  if (ride.phase === 'board') {
    if (ride.t >= WHEEL_RIDE.BOARD_SEC) {
      ride.phase = 'ride';
      ride.t = 0;
      ride.rideT = 0;
      events.push({ type: 'depart' });
    }
    return events;
  }

  if (ride.phase === 'ride' || ride.phase === 'return') {
    ride.rideT += dt;
    // tap-to-end-early: unlocked EARLY_TAP_SEC into the ride, graceful
    if (ride.phase === 'ride' && !ride.hintFired && ride.rideT >= WHEEL_RIDE.EARLY_TAP_SEC) {
      ride.hintFired = true;
      events.push({ type: 'hintReady' });
    }
    if (
      ride.phase === 'ride' &&
      input.tapped &&
      ride.rideT >= WHEEL_RIDE.EARLY_TAP_SEC &&
      !ride.returned
    ) {
      ride.returned = true;
      ride.phase = 'return';
      events.push({ type: 'returnStarted' });
    }
    const fullOmega =
      ((ride.phase === 'return' ? WHEEL_RIDE.RETURN_RPM : WHEEL_RIDE.RIDE_RPM) * TAU) / 60;
    const remaining = TAU - ride.rideAngle;
    const ramp = Math.min(1, ride.rideT / WHEEL_RIDE.SPIN_UP_SEC);
    const easeOut = Math.min(1, remaining / WHEEL_RIDE.EASE_OUT_ANG);
    const omega = Math.max(WHEEL_RIDE.EASE_MIN_OMEGA, fullOmega * ramp * easeOut);
    const step = Math.min(remaining, omega * dt);
    ride.theta += step;
    ride.rideAngle += step;
    if (!ride.apexFired && ride.rideAngle >= WHEEL_RIDE.APEX_AT) {
      ride.apexFired = true;
      events.push({ type: 'apex' });
    }
    if (ride.rideAngle >= TAU - 1e-9) {
      ride.rideAngle = TAU;
      ride.phase = 'disembark';
      ride.t = 0;
      events.push({ type: 'arrived' });
    }
    return events;
  }

  if (ride.phase === 'disembark') {
    if (ride.t >= WHEEL_RIDE.DISEMBARK_SEC) finishNow();
    return events;
  }

  return events;
}

/**
 * V6.1/G3 (FINAL-WAVE B8): which caption the apex beat shows — the night
 * line ONLY in the 'night' band (the lights already glow, BAND_GLOW 0.8);
 * dawn/day/dusk (and junk) keep the classic line, so souvenir timing and
 * every other apex beat stay byte-identical. Pure (band id → key) —
 * headless-tested by test/ferrisWheel.test.js; the view passes
 * `bandAt(now()).band` at the apex event.
 * @param {string|null|undefined} band dayNight band id
 * @returns {'park.wheel.apexNight'|'park.wheel.apex'}
 */
export function apexCaptionKey(band) {
  return band === 'night' ? 'park.wheel.apexNight' : 'park.wheel.apex';
}

// ═══════════════════════════════════════════════════════════════════════════
// VIEW — three.js build + the in-scene ride (park/parkScene.js is the only
// caller; the plaza scene keeps rendering, so day-band/weather stay live).
// ═══════════════════════════════════════════════════════════════════════════

/** t() first, then the owned v6-park EN/DE table (E2/E3's tx() pattern). */
function tx(key) {
  const v = t(key);
  if (v !== key) return v;
  return (getLang() === 'de' ? PARK_DE : PARK_EN)[key] ?? key;
}

/** Rim fairy-glow per band (no extra draw calls — emissive on the rim mat). */
const BAND_GLOW = Object.freeze({ day: 0, dawn: 0.1, dusk: 0.5, night: 0.8 });

/** Scoped ride overlay chrome (v6fw- prefix — coasterRide CSS precedent). */
const OVERLAY_CSS = `
.v6fw-root{position:fixed;inset:0;z-index:60;pointer-events:auto;font-family:inherit;user-select:none;-webkit-user-select:none;touch-action:none;}
.v6fw-caption{position:absolute;left:50%;bottom:calc(var(--safe-bottom, 0px) + 3.4rem);transform:translateX(-50%) translateY(0.375rem);max-width:24rem;padding:0 1rem;color:#FFF7EE;font-size:1rem;font-weight:800;line-height:1.35;text-align:center;text-shadow:0 2px 8px rgba(0,0,0,.45);opacity:0;transition:opacity .25s ease,transform .25s ease;}
.v6fw-caption.v6fw-in{opacity:1;transform:translateX(-50%);}
.v6fw-hint{position:absolute;left:50%;bottom:calc(var(--safe-bottom, 0px) + 1.1rem);transform:translateX(-50%);padding:0.375rem 0.875rem;border-radius:999px;background:rgba(23,18,16,.6);color:#FFF7EE;font-size:0.75rem;font-weight:800;white-space:nowrap;opacity:0;transition:opacity .3s ease;}
.v6fw-hint.v6fw-in{opacity:1;}
@media (prefers-reduced-motion: reduce){.v6fw-caption,.v6fw-hint{transition:none;}}
`;

/** Caption auto-clear dwell (s). */
const CAPTION_SEC = 3.4;
/** Apex lean-out-and-wave beat length (s). */
const APEX_BEAT_SEC = 4.5;
/** Camera orbit radius around the axle during the ride (m, wheel-local). */
const CAM_ORBIT_R = 7.2;
/** Enter/exit camera tween seconds. */
const CAM_ENTER_SEC = 1.6;
const CAM_EXIT_SEC = 1.4;

/**
 * Build + mount the procedural wheel at E1's reserved anchor. Returns the
 * handle parkScene keeps: update(dt) every frame (ambient spin OR the active
 * ride drive), setBand(band) for the rim night glow, dispose() on scene
 * dispose. Exactly ONE InstancedMesh/Mesh per WHEEL_BATCHES row (≤6 calls).
 * @param {THREE.Object3D} parent scene/plaza group
 * @param {{x: number, z: number, rotY: number}} anchor layout.anchors.ferrisWheel
 * @param {{reducedMotion?: boolean}} [opts]
 */
export function mountFerrisWheel(parent, anchor, opts = {}) {
  const reduceMotion = opts.reducedMotion === true;
  const ledger = createWheelLedger();
  const N = WHEEL.GONDOLAS;

  const group = new THREE.Group();
  group.name = 'ferrisWheel';
  group.position.set(anchor.x, 0, anchor.z);
  group.rotation.y = anchor.rotY ?? 0;
  parent.add(group);

  // axle-centered rotor (rims + spokes spin; cabins are computed upright)
  const rotor = new THREE.Group();
  rotor.name = 'ferrisWheelRotor';
  rotor.position.set(0, WHEEL.HUB_HEIGHT, 0);
  group.add(rotor);

  const matCream = ledger.track(
    new THREE.MeshStandardMaterial({ color: '#FBF3E4', roughness: 0.7 }),
    'material'
  );
  const matRim = ledger.track(
    new THREE.MeshStandardMaterial({
      color: '#F2A7BE',
      roughness: 0.55,
      emissive: '#FF9FC2',
      emissiveIntensity: 0,
    }),
    'material'
  );
  const matCabin = ledger.track(
    new THREE.MeshStandardMaterial({ color: '#FFFFFF', roughness: 0.55 }),
    'material'
  );
  const matRoof = ledger.track(
    new THREE.MeshStandardMaterial({ color: '#FFFFFF', roughness: 0.6 }),
    'material'
  );
  const matPlat = ledger.track(
    new THREE.MeshStandardMaterial({ color: '#D9C6A8', roughness: 1 }),
    'material'
  );

  const tmpM = new THREE.Matrix4();
  const tmpQ = new THREE.Quaternion();
  const tmpV = new THREE.Vector3();
  const tmpS = new THREE.Vector3();
  const Y_AXIS = new THREE.Vector3(0, 1, 0);

  // ---- batch 1: the two rims (one InstancedMesh, torus ×2) ----------------
  const rimGeo = ledger.track(
    new THREE.TorusGeometry(WHEEL.RADIUS, WHEEL.RIM_TUBE_R, 10, 48),
    'geometry'
  );
  const rims = new THREE.InstancedMesh(rimGeo, matRim, 2);
  for (let k = 0; k < 2; k++) {
    tmpM.makeTranslation(0, 0, k === 0 ? WHEEL.RIM_Z : -WHEEL.RIM_Z);
    rims.setMatrixAt(k, tmpM);
  }
  rims.instanceMatrix.needsUpdate = true;
  rotor.add(rims);

  // ---- batch 2: spokes (offset half a bay from the gondola pivots) --------
  const spokeGeo = ledger.track(
    new THREE.CylinderGeometry(WHEEL.SPOKE_R, WHEEL.SPOKE_R, 1, 6),
    'geometry'
  );
  const spokes = new THREE.InstancedMesh(spokeGeo, matCream, N * 2);
  for (let k = 0; k < N * 2; k++) {
    const a = Math.PI / N + ((k % N) * TAU) / N; // rotor-local spoke angles
    const z = k < N ? WHEEL.RIM_Z : -WHEEL.RIM_Z;
    tmpQ.setFromAxisAngle(new THREE.Vector3(0, 0, 1), a - Math.PI / 2);
    tmpV.set((Math.cos(a) * WHEEL.RADIUS) / 2, (Math.sin(a) * WHEEL.RADIUS) / 2, z);
    tmpS.set(1, WHEEL.RADIUS, 1);
    tmpM.compose(tmpV, tmpQ, tmpS);
    spokes.setMatrixAt(k, tmpM);
  }
  spokes.instanceMatrix.needsUpdate = true;
  rotor.add(spokes);

  // ---- batch 3: static structure (A-frame legs, axle, hub caps, brace) ----
  const structGeo = ledger.track(new THREE.CylinderGeometry(0.11, 0.13, 1, 8), 'geometry');
  const structure = new THREE.InstancedMesh(structGeo, matCream, 8);
  /** stretch a unit-Y cylinder between two points */
  const strut = (idx, ax, ay, az, bx, by, bz, thick = 1) => {
    tmpV.set(bx - ax, by - ay, bz - az);
    const len = tmpV.length();
    tmpQ.setFromUnitVectors(Y_AXIS, tmpV.normalize());
    tmpS.set(thick, len, thick);
    tmpV.set((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2);
    tmpM.compose(tmpV, tmpQ, tmpS);
    structure.setMatrixAt(idx, tmpM);
  };
  const H = WHEEL.HUB_HEIGHT;
  strut(0, -1.55, 0, 1.5, 0, H, WHEEL.RIM_Z + 0.14); //  front A-frame
  strut(1, 1.55, 0, 1.5, 0, H, WHEEL.RIM_Z + 0.14);
  strut(2, -1.55, 0, -1.5, 0, H, -WHEEL.RIM_Z - 0.14); // back A-frame
  strut(3, 1.55, 0, -1.5, 0, H, -WHEEL.RIM_Z - 0.14);
  strut(4, 0, H, -WHEEL.RIM_Z - 0.3, 0, H, WHEEL.RIM_Z + 0.3, 1.4); // axle
  strut(5, 0, H, WHEEL.RIM_Z + 0.1, 0, H, WHEEL.RIM_Z + 0.3, WHEEL.HUB_R / 0.11); // hub caps
  strut(6, 0, H, -WHEEL.RIM_Z - 0.3, 0, H, -WHEEL.RIM_Z - 0.1, WHEEL.HUB_R / 0.11);
  strut(7, -1.05, H * 0.35, 1.02, 1.05, H * 0.35, 1.02); // front cross-brace
  structure.instanceMatrix.needsUpdate = true;
  group.add(structure);

  // ---- batch 4+5: gondola cabins + tiny roofs (instanceColor pastels) -----
  const cabinGeo = ledger.track(
    new THREE.CapsuleGeometry(WHEEL.GONDOLA_R, 0.3, 5, 14),
    'geometry'
  );
  const cabins = new THREE.InstancedMesh(cabinGeo, matCabin, N);
  const roofGeo = ledger.track(new THREE.ConeGeometry(0.5, 0.34, 12), 'geometry');
  const roofs = new THREE.InstancedMesh(roofGeo, matRoof, N);
  const color = new THREE.Color();
  for (let i = 0; i < N; i++) {
    cabins.setColorAt(i, color.set(GONDOLA_COLORS[i % GONDOLA_COLORS.length]));
    roofs.setColorAt(i, color.set(GONDOLA_ROOFS[i % GONDOLA_ROOFS.length]));
  }
  cabins.instanceColor.needsUpdate = true;
  roofs.instanceColor.needsUpdate = true;
  group.add(cabins, roofs);

  // ---- batch 6: boarding platform (plaza side of the bottom gondola) ------
  const platGeo = ledger.track(new THREE.BoxGeometry(2.4, 0.16, 1.5), 'geometry');
  const platform = new THREE.Mesh(platGeo, matPlat);
  platform.position.set(0, 0.08, 1.55);
  group.add(platform);

  // ---- per-frame cabin placement (the tested pure transform, verbatim) ----
  let theta = Math.PI / 7; // pleasant static offset for reduced motion
  const identityQ = new THREE.Quaternion();
  const cabinScaleV = new THREE.Vector3(1, 0.72, 0.68); // squashed inside the rim gap
  const roofScaleV = new THREE.Vector3(1, 1, 0.68);
  function writeCabins() {
    for (let i = 0; i < N; i++) {
      const g = gondolaTransform(theta, i, N);
      // cabinRot(-theta) cancels rimRot(theta) → identity: upright forever
      tmpV.set(g.cx, WHEEL.HUB_HEIGHT + g.cy, 0);
      tmpM.compose(tmpV, identityQ, cabinScaleV);
      cabins.setMatrixAt(i, tmpM);
      tmpV.set(g.px, WHEEL.HUB_HEIGHT + g.py - 0.2, 0);
      tmpM.compose(tmpV, identityQ, roofScaleV);
      roofs.setMatrixAt(i, tmpM);
    }
    cabins.instanceMatrix.needsUpdate = true;
    roofs.instanceMatrix.needsUpdate = true;
    rotor.rotation.z = theta;
  }
  writeCabins();

  /** @type {null | {update(dt: number): void, cancel(): void}} */
  let activeRide = null;

  const handle = {
    group,
    /** @returns {number} current wheel angle (rad) */
    getTheta: () => theta,
    /** the active ride owns theta (ambient advance pauses meanwhile) */
    setTheta(v) {
      theta = v;
    },
    /** world position of gondola i's seat → out (for the ride + camera) */
    gondolaWorld(i, out) {
      const g = gondolaTransform(theta, i, N);
      out.set(g.cx, WHEEL.HUB_HEIGHT + g.cy, 0);
      return group.localToWorld(out);
    },
    /** rim fairy glow per plaza band (no extra draw calls) */
    setBand(band) {
      matRim.emissiveIntensity = BAND_GLOW[band] ?? 0;
    },
    isRiding: () => activeRide != null,
    /** @param {object|null} ride the startWheelRide driver (internal) */
    _attachRide(ride) {
      activeRide = ride;
    },
    update(dt) {
      if (activeRide) {
        activeRide.update(dt);
      } else if (!reduceMotion) {
        theta += (WHEEL.AMBIENT_RPM * TAU * dt) / 60;
      }
      writeCabins();
    },
    /** scene exit safety: force-finish an in-flight ride without tweens */
    cancelRide() {
      activeRide?.cancel();
    },
    dispose() {
      cancelRide2();
      cabins.dispose();
      roofs.dispose();
      rims.dispose();
      spokes.dispose();
      structure.dispose();
      ledger.disposeAll();
      group.removeFromParent();
    },
  };
  // dispose() must not recurse through a stale activeRide after cancel
  function cancelRide2() {
    try {
      activeRide?.cancel();
    } catch { /* ride already gone */ }
    activeRide = null;
  }
  return handle;
}

/**
 * The apex souvenir (E2's coasterRide takeSouvenir pattern): one
 * captureFrame from the money-shot camera → IndexedDB photo gallery.
 * Fire-and-forget; photoStore arrives via dynamic import so this module
 * stays node-importable.
 */
async function takeApexSouvenir({ sceneManager, store, audio }, onSaved) {
  if (!sceneManager?.captureFrame) return; // no HUD camera in the park (documented)
  try {
    audio?.play?.('photo.shutter');
    const blob = await sceneManager.captureFrame();
    if (!blob) return;
    const photoStore = await import('../core/photoStore.js');
    const res = await photoStore.add(blob, {
      at: now(),
      w: typeof innerWidth !== 'undefined' ? innerWidth : 0,
      h: typeof innerHeight !== 'undefined' ? innerHeight : 0,
      frame: 'ferrisWheel',
    });
    if (res.ok && store) {
      const total = await photoStore.count();
      store.update((state) => {
        const g = state.gallery ?? { count: 0, lastAddedAt: 0, hintShown: false };
        state.gallery = { hintShown: g.hintShown === true, ...mirrorSlice(total, res.meta.at) };
      });
      store.emit?.('galleryChanged', { id: res.id });
      onSaved?.();
    }
  } catch (err) {
    console.warn('[ferrisWheel] souvenir failed:', err?.message);
  }
}

/**
 * Start the ~45 s gentle ride IN the park scene (no scene switch — the plaza,
 * its day-band rig and E3's lights stay live below). Resolves true once the
 * ride actually started; ctx.onDone fires exactly once when Gooby is back on
 * the plaza and the camera is restored (E2's onDone contract).
 * @param {{wheel: ReturnType<typeof mountFerrisWheel>, camera: THREE.Camera,
 *   gooby: {group: THREE.Group, play: Function, setEmotion: Function},
 *   audio?: object, store?: object, sceneManager?: object,
 *   reducedMotion?: boolean, onDone?: () => void,
 *   getRestorePose?: () => {pos: number[], look: number[]}}} ctx
 * @returns {Promise<boolean>}
 */
export async function startWheelRide(ctx) {
  const { wheel, camera, gooby } = ctx ?? {};
  if (!wheel || !camera || !gooby) {
    console.warn('[ferrisWheel] startWheelRide needs ctx.wheel/camera/gooby');
    return false;
  }
  if (wheel.isRiding()) return false;
  const audio = ctx.audio ?? null;
  const reducedMotion = ctx.reducedMotion === true;
  const ride = createWheelRide({ reducedMotion, theta0: wheel.getTheta() });

  // ---- camera lease: snapshot now, restore in the finish path (E2) --------
  const camSnapshot = {
    pos: camera.position.clone(),
    quat: camera.quaternion.clone(),
    fov: camera.fov,
  };
  const group = wheel.group;
  group.updateMatrixWorld(true); // localToWorld below needs a fresh matrix
  const seatV = new THREE.Vector3();
  const camV = new THREE.Vector3();
  const lookV = new THREE.Vector3();
  const fromPos = new THREE.Vector3();
  const fromLook = new THREE.Vector3();
  const goobyFrom = new THREE.Vector3();
  const platformWorld = group.localToWorld(new THREE.Vector3(0.2, 0, 1.55));
  const goobySnapshot = { scale: gooby.group.scale.x };

  // ---- overlay: caption + tap hint; full-screen → plaza input is blocked --
  let overlay = null;
  let styleEl = null;
  let captionEl = null;
  let hintEl = null;
  let captionT = 0;
  let tapQueued = false;
  if (typeof document !== 'undefined') {
    styleEl = document.createElement('style');
    styleEl.textContent = OVERLAY_CSS;
    document.head.appendChild(styleEl);
    overlay = document.createElement('div');
    overlay.className = 'v6fw-root';
    overlay.innerHTML = '<div class="v6fw-caption"></div><div class="v6fw-hint"></div>';
    document.body.appendChild(overlay);
    captionEl = overlay.querySelector('.v6fw-caption');
    hintEl = overlay.querySelector('.v6fw-hint');
    hintEl.textContent = tx('park.wheel.skipHint');
    overlay.addEventListener('pointerdown', () => {
      tapQueued = true;
    });
  }
  const showCaption = (key) => {
    if (!captionEl) return;
    captionEl.textContent = tx(key);
    captionEl.classList.add('v6fw-in');
    captionT = CAPTION_SEC;
  };

  /** camera drive mode: 'enter' | 'follow' | 'exit' (tween owns enter/exit) */
  let camMode = 'enter';
  let camTween = null;
  let apexBeatT = 0;
  let goobyPhase = 'dash'; // dash → hop → seated → hopOff → off
  let hopFrom = null;
  let doneFired = false;
  let finished = false;

  /** wheel-local ride camera for travel angle a (orbits plaza → behind). */
  function followPose(a, outPos, outLook) {
    const g = gondolaTransform(ride.theta, ride.boardIndex);
    const cy = WHEEL.HUB_HEIGHT + g.cy;
    // orbit azimuth: plaza side (+z) while boarding/low, swings behind (−z)
    // for the rise so the WHOLE plaza spreads out under the apex shot, and
    // retraces on the descent. Smooth in travel angle — dt-independent.
    const up = Math.min(1, Math.max(0, (a - 0.35) / 2.05)); //   0..1 by ~2.4 rad
    const downA = TAU - 1.4; //                                 swing back late
    const down = Math.min(1, Math.max(0, (a - downA) / 1.1));
    const az = Math.PI * (up * up * (3 - 2 * up)) * (1 - down * down * (3 - 2 * down));
    // a true orbit (x tracks sin) so the camera never crosses the wheel disc
    outPos.set(
      Math.sin(az) * CAM_ORBIT_R * 0.9,
      Math.max(1.6, cy + 1.35),
      Math.cos(az) * CAM_ORBIT_R
    );
    // look z blends smoothly plaza-side → over-the-plaza (no snap at az π/2)
    outLook.set(g.cx * 0.5, cy - 0.35, 0.5 - Math.cos(az) * 2.1);
    group.localToWorld(outPos);
    group.localToWorld(outLook);
  }

  /** RM/board static shot (wheel-local → world). */
  function staticPose(px, py, pz, lx, ly, lz, outPos, outLook) {
    outPos.set(px, py, pz);
    outLook.set(lx, ly, lz);
    group.localToWorld(outPos);
    group.localToWorld(outLook);
  }

  const seatLocal = () => {
    const g = gondolaTransform(ride.theta, ride.boardIndex);
    return seatV.set(g.cx, WHEEL.HUB_HEIGHT + g.cy + 0.1, 0.06);
  };

  /** exactly-once finish: restore camera/gooby, drop overlay, fire onDone. */
  function finish({ instant = false } = {}) {
    if (finished) return;
    finished = true;
    camTween?.cancel();
    camTween = null;
    const cleanup = () => {
      wheel._attachRide(null);
      overlay?.remove();
      styleEl?.remove();
      overlay = null;
      styleEl = null;
      gooby.group.scale.setScalar(goobySnapshot.scale);
      try {
        gooby.setEmotion('happy');
      } catch { /* rig may be disposing */ }
      if (!doneFired) {
        doneFired = true;
        try {
          ctx.onDone?.();
        } catch (err) {
          console.error('[ferrisWheel] onDone failed:', err);
        }
      }
      if (import.meta.env?.DEV && typeof window !== 'undefined' && window.__wheelRide === driver) {
        delete window.__wheelRide;
      }
    };
    if (instant || typeof document === 'undefined') {
      camera.position.copy(camSnapshot.pos);
      camera.quaternion.copy(camSnapshot.quat);
      camera.fov = camSnapshot.fov;
      camera.updateProjectionMatrix?.();
      cleanup();
      return;
    }
    // graceful hand-back: tween to the pose the plaza pan loop will write
    const restore = ctx.getRestorePose?.() ?? null;
    fromPos.copy(camera.position);
    camera.getWorldDirection(lookV);
    fromLook.copy(camera.position).addScaledVector(lookV, 10);
    const toPos = restore ? new THREE.Vector3(...restore.pos) : camSnapshot.pos.clone();
    const toLook = restore
      ? new THREE.Vector3(...restore.look)
      : fromLook.clone();
    camMode = 'exit';
    camTween = tween({
      duration: CAM_EXIT_SEC,
      ease: easings.easeInOutQuad,
      onUpdate: (v) => {
        camera.position.lerpVectors(fromPos, toPos, v);
        camV.lerpVectors(fromLook, toLook, v);
        camera.lookAt(camV);
      },
      onComplete: cleanup,
    });
  }

  /** route one pure ride event to chrome/audio/Gooby/camera beats. */
  function handleEvent(event) {
    switch (event.type) {
      case 'board':
        showCaption('park.wheel.board');
        audio?.play?.('gooby.squeakHappy');
        if (!reducedMotion) {
          goobyPhase = 'hop';
          hopFrom = goobyFrom.copy(gooby.group.position);
          gooby.play?.('jump')?.catch?.(() => {});
        }
        break;
      case 'depart':
        audio?.play?.('pipe.rotate'); // gondola door clunk
        gooby.play?.('sitDrive', { loop: 'hold' })?.catch?.(() => {});
        break;
      case 'apex': {
        // V6.1/G3 (B8): band-aware apex line — night rides get the twinkle.
        showCaption(apexCaptionKey(bandAt(now()).band));
        audio?.play?.('gooby.squeakHappy');
        apexBeatT = APEX_BEAT_SEC;
        try {
          gooby.setEmotion('ecstatic');
        } catch { /* emotion optional */ }
        gooby.play?.('wave', { loop: true })?.catch?.(() => {});
        // the "photo spot": automatic souvenir from the money-shot camera
        takeApexSouvenir(ctx, () => showCaption('park.wheel.photoSaved'));
        break;
      }
      case 'hintReady':
        hintEl?.classList.add('v6fw-in');
        break;
      case 'returnStarted':
        hintEl?.classList.remove('v6fw-in');
        audio?.play?.('ui.pick');
        break;
      case 'arrived':
        showCaption('park.wheel.done');
        audio?.play?.('jingle.arrival');
        try {
          gooby.setEmotion('happy');
        } catch { /* emotion optional */ }
        if (!reducedMotion) {
          goobyPhase = 'hopOff';
          hopFrom = goobyFrom.copy(gooby.group.position);
          gooby.play?.('jump')?.catch?.(() => {});
        }
        break;
      case 'done':
        finish();
        break;
      default:
        break;
    }
  }

  /** per-frame Gooby placement (deterministic — no tweens to leak). */
  function driveGooby(dt) {
    if (reducedMotion) {
      seatLocal();
      group.localToWorld(seatV);
      gooby.group.position.copy(seatV);
      gooby.group.rotation.y = group.rotation.y + Math.PI;
      gooby.group.scale.setScalar(RIDER_SCALE);
      return;
    }
    if (goobyPhase === 'dash') {
      // excited trot from wherever the stroll left him to the platform
      camV.copy(platformWorld).sub(gooby.group.position);
      camV.y = 0;
      const d = camV.length();
      if (d > 0.12) {
        camV.normalize();
        const step = Math.min(d, WHEEL_RIDE.DASH_SPEED * dt);
        gooby.group.position.addScaledVector(camV, step);
        gooby.group.rotation.y = Math.atan2(camV.x, camV.z);
        gooby.group.position.y = Math.abs(Math.sin(ride.totalT * 9)) * 0.14;
      } else {
        gooby.group.position.y = 0;
      }
      return;
    }
    if (goobyPhase === 'hop') {
      const s = Math.min(1, ride.t / WHEEL_RIDE.BOARD_SEC);
      const e = easings.easeInOutQuad(s);
      seatLocal();
      group.localToWorld(seatV);
      gooby.group.position.lerpVectors(hopFrom, seatV, e);
      gooby.group.position.y += Math.sin(Math.min(1, s * 1.15) * Math.PI) * 0.85;
      gooby.group.scale.setScalar(1 + (RIDER_SCALE - 1) * e);
      gooby.group.rotation.y = group.rotation.y + Math.PI * e;
      if (s >= 1) goobyPhase = 'seated';
      return;
    }
    if (goobyPhase === 'seated') {
      seatLocal();
      if (apexBeatT > 0) {
        apexBeatT -= dt;
        // lean-out-and-wave beat: smoothstep trapezoid 0→1→0 over the beat so
        // Gooby rises out of the cabin toward the apex camera (the wave must
        // READ over the cabin rim) and settles back without a snap.
        const elapsed = APEX_BEAT_SEC - apexBeatT;
        const win = Math.max(0, Math.min(1, elapsed / 0.8, apexBeatT / 0.8));
        const w = win * win * (3 - 2 * win);
        seatV.z -= 0.38 * w;
        seatV.y += 0.22 * w;
        if (apexBeatT <= 0) {
          gooby.play?.('sitDrive', { loop: 'hold' })?.catch?.(() => {});
        }
      }
      group.localToWorld(seatV);
      gooby.group.position.copy(seatV);
      gooby.group.rotation.y = group.rotation.y + Math.PI;
      gooby.group.scale.setScalar(RIDER_SCALE);
      return;
    }
    if (goobyPhase === 'hopOff') {
      const s = Math.min(1, ride.t / WHEEL_RIDE.DISEMBARK_SEC);
      const e = easings.easeInOutQuad(s);
      gooby.group.position.lerpVectors(hopFrom, platformWorld, e);
      gooby.group.position.y += Math.sin(s * Math.PI) * 0.7;
      gooby.group.scale.setScalar(RIDER_SCALE + (1 - RIDER_SCALE) * e);
      if (s >= 1) {
        goobyPhase = 'off';
        gooby.play?.('happyBounce')?.catch?.(() => {});
      }
    }
  }

  const driver = {
    ride,
    update(dt) {
      if (finished) return;
      const tapped = tapQueued;
      tapQueued = false;
      for (const event of stepWheelRide(ride, dt, { tapped })) handleEvent(event);
      wheel.setTheta(ride.theta);
      driveGooby(dt);
      if (captionT > 0) {
        captionT -= dt;
        if (captionT <= 0) captionEl?.classList.remove('v6fw-in');
      }
      if (camMode === 'follow' && !reducedMotion) {
        followPose(ride.rideAngle, camV, lookV);
        // gentle per-frame smoothing keeps the follow dreamy, not rigid
        const k = Math.min(1, dt * 3.2);
        camera.position.lerp(camV, k);
        fromLook.lerp(lookV, k);
        camera.lookAt(fromLook);
      }
    },
    cancel() {
      finish({ instant: true });
    },
  };

  // ---- lift-off: enter camera tween, then hand over to the follow rig -----
  wheel._attachRide(driver);
  if (import.meta.env?.DEV && typeof window !== 'undefined') window.__wheelRide = driver;
  try {
    audio?.play?.('ui.open');
    if (reducedMotion) {
      // static apex shot: one cut, caption, no camera motion at all
      staticPose(1.6, WHEEL.HUB_HEIGHT + WHEEL.RADIUS - 0.4, -6.4, 0, WHEEL.HUB_HEIGHT + WHEEL.RADIUS - 1.2, 3, camV, lookV);
      camera.position.copy(camV);
      camera.lookAt(lookV);
      fromLook.copy(lookV);
      camMode = 'follow';
      hintEl?.classList.add('v6fw-in'); // tap ends the hold any time
    } else {
      fromPos.copy(camera.position);
      camera.getWorldDirection(lookV);
      fromLook.copy(camera.position).addScaledVector(lookV, 10);
      followPose(0, camV, lookV);
      const toPos = camV.clone();
      const toLook = lookV.clone();
      camTween = tween({
        duration: CAM_ENTER_SEC,
        ease: easings.easeInOutQuad,
        onUpdate: (v) => {
          if (finished) return;
          camera.position.lerpVectors(fromPos, toPos, v);
          lookV.lerpVectors(fromLook, toLook, v);
          camera.lookAt(lookV);
        },
        onComplete: () => {
          fromLook.copy(toLook);
          camMode = 'follow';
        },
      });
    }
    return true;
  } catch (err) {
    console.error('[ferrisWheel] ride failed to start:', err);
    finish({ instant: true });
    return false;
  }
}
