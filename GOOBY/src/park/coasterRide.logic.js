// V6/E2 — Funkelpark signature coaster: PURE ride logic (PLAN6 Wave E/E2).
// No three/DOM imports — node:test drives the whole ride headlessly
// (test/coasterRide.test.js) and park/coasterRide.js renders THIS simulation
// 1:1. This is a park ATTRACTION on the single-coaster ruling: NO fail
// state, NO score, NO payout, NO cover, NO game-count pin — the only
// "input" is the optional hold-to-hands-up delight.
//
// The circuit (LAYOUT below, ~53 s ride): station platform → chain-lift
// ascent (slow clank) → flat crest turn (anticipation) → triple first drop
// → launch straight → DOUBLE VERTICAL LOOP (the wow beat) → ride-photo
// straight (flash!) → camelback + bunny hops → long brake run → home turn
// back into the station. Closure (all four left turns, loop drift
// compensated by the s-curve) is proven by the ≤1 mm socket test.
//
// Physics-lite speed profile (energy-based, deterministic, dt-driven,
// fixed substeps, zero rng): chain lift = constant crawl; free sections
// integrate dv = (−G·grade − friction·v)·dt off the spline's actual slope;
// a launch boost before the loops guarantees loop clearance (real coasters
// do this too); the brake run bleeds speed back to station crawl. Hard
// clamps keep v in [VMIN_RUN, VMAX] on free track — the ride can NEVER
// stall and NEVER runs away (test-pinned).
//
// Sequencer ruling (PLAN6 E2 "director OR self-driven — justify"): the ride
// is ONE continuous spline-following camera move, which the cutscene
// director's op vocabulary (pushIn/pullBack/restore dollies) cannot express
// without adding a new op kind to A1's owned systems/cutscene.js. So the
// ride runs a SELF-DRIVEN sequencer that mirrors the director's PURE
// semantics instead: arc-length-keyed cues (captions/sfx fire once, in
// order), CUTSCENE.HOLD_SKIP_SEC-style hold-to-skip that jumps to the brake
// run, and a WATCHDOG_SEC force-finish so the ride can never trap the
// player (risk #5 discipline). §E0.1-2: every exact number is frozen here.

import { assembleTrack, pointAt } from './trackPieces.js';

/** §E0.1-2: the binding coaster numbers — all speeds/lengths in track units
 * (1 unit = 1 toy-car-kit GLB unit); WORLD_SCALE converts to world meters. */
export const COASTER = Object.freeze({
  /** Track units → rendered world meters (park scale — cute, not huge). */
  WORLD_SCALE: 2,
  /** Gravity in track units/s² (9.8 m/s² ÷ WORLD_SCALE). */
  G: 4.9,
  /** Linear rolling drag (per second, ×v) on free track. */
  FRICTION: 0.022,
  /** Central-difference half-step (units) for the spline grade. */
  GRADE_H: 0.35,
  /** Station departure crawl + its approach accel. */
  DEPART_SPEED: 2.2,
  DEPART_ACCEL: 0.9,
  /** Chain-lift crawl (the clank ascent) + crest roll-over speed. */
  LIFT_SPEED: 1.05,
  CREST_SPEED: 1.4,
  /** Zone-target approach rate (lift/crest/home, units/s²). */
  APPROACH_RATE: 2.5,
  /** Launch boost before the loops (guarantees loop clearance: apex needs
   * v² ≥ 2·G·2r ≈ 33.3 → base ≥ 6.5; 7.2 leaves a comfy margin). */
  BOOST_SPEED: 7.2,
  BOOST_ACCEL: 4.5,
  /** Free-track clamps: the ride never stalls, never runs away. */
  VMIN_RUN: 2.2,
  VMAX: 8.5,
  /** Brake run: bleed rate + target crawl back to the station. */
  BRAKE_DECEL: 2.6,
  BRAKE_TARGET: 2.2,
  STATION_SPEED: 2.2,
  /** Final ease: last units before the stop point + the crawl floor. */
  END_EASE_LEN: 3.5,
  END_MIN_V: 0.3,
  /** Stop epsilon (units left when the ride counts as arrived). */
  END_STOP_EPS: 0.05,
  /** Boarding pause before departure (captions + restraint check). */
  BOARD_SEC: 4,
  /** Deterministic integration substep ceiling (s). */
  MAX_SUBSTEP: 1 / 120,
  /** Hard force-finish (mirrors systems/cutscene.js watchdog semantics). */
  WATCHDOG_SEC: 90,
  /** Hold-to-skip fill seconds (mirrors CUTSCENE.HOLD_SKIP_SEC). */
  HOLD_SKIP_SEC: 0.6,
  /** Speed the train re-enters at when skipping to the brake run. */
  SKIP_ENTRY_SPEED: 4.5,
  /** Camera rig (track units): chase offset behind/above + look-ahead. */
  CAM_BACK: 3,
  CAM_UP: 1.6,
  CAM_LOOKAHEAD: 3.8,
  CAM_LOOK_UP: 0.5,
  /** Loop-beat camera — EXTERIOR tracking shot (the plan's "exterior or
   * POV — whichever reads best" ruling): at toy-kit scale the riding circle
   * is r 1.7, so from ANY interior POV the ribbon is < 2.6 units away
   * across the entire FOV (verified by live raycast — a full-orange frame).
   * The chase cam therefore DOLLIES OUT to the valley vantage over
   * ROLL_BLEND_LEN and TRACKS the train through both inversions: the
   * controlled roll plays out on the TRAIN, the camera itself never rolls.
   * LOOP_TRACK_LERP = how hard the look-at follows the cart vs the loop
   * center (1 = glued to the cart). */
  LOOP_TRACK_LERP: 0.65,
  /** Station boarding shot (track units, tangent-anchored at s = 0). */
  SHOT_SIDE: 2.4,
  SHOT_BACK: 1.8,
  SHOT_UP: 1.3,
  SHOT_LOOK_AHEAD: 0.9,
  SHOT_LOOK_UP: 0.5,
  /** Loop dolly blend margin (arc units): the exterior-vantage blend eases
   * in over the first ROLL_BLEND_LEN of the loop span and back out over the
   * last (12-unit flight ÷ 6 units ≈ 11 u/s camera speed — smooth, no cuts). */
  ROLL_BLEND_LEN: 6,
  /** Station-shot → chase-cam blend seconds after departure. */
  CAM_BLEND_SEC: 1.5,
  /** Ride photo: flash point fraction along the photo straight + caption
   * lead distance (units before the flash). */
  PHOTO_FRACTION: 0.55,
  PHOTO_LEAD: 1.6,
  /** Hands-up: sparkle cadence while held in a window + the held seconds
   * that earn the 'wheee' (all windows are ≥ 3 s long at ride speed). */
  HANDS_SPARKLE_EVERY: 0.22,
  WHEEE_MIN_SEC: 1.5,
  /** 2-cart train: arc-length gap between cart centers. */
  CART_GAP: 1.15,
});

/**
 * The authored circuit — 28 toy-car-kit pieces, 4 left corners (360°), the
 * two loops' 1-unit left drifts compensated by the s-curve on the brake
 * leg, lift climb (+1.5) balanced by the triple drop (−1.5) and both hill
 * pairs closing to 0. assembleTrack proves closure to < 1 mm.
 */
export const LAYOUT = Object.freeze([
  'straight', 'straight', //                    station platform
  'bumpUp', 'bumpUp', 'bumpUp', //              chain lift, +1.5
  'cornerL', //                                 flat crest turn (anticipation)
  'bumpDown', 'bumpDown', 'bumpDown', //        triple first drop, −1.5
  'straight', //                                launch straight
  'loop', 'loop', //                            THE double loop (wow beat)
  'straight', //                                ride-photo straight
  'cornerL', //                                 turn 2
  'bumpUp', 'bumpDown', //                      camelback
  'straight', //                                valley breather
  'bumpUp', 'bumpDown', //                      bunny hop
  'cornerL', //                                 turn 3
  'curve', //                                   s-drift (loop compensation)
  'straight', 'straight', 'straight', //        brake run…
  'straight', 'straight', 'straight', //        …six straights
  'cornerL', //                                 home turn into the station
]);

/** Per-piece ride roles (parallel to LAYOUT) — the zone source of truth. */
export const ROLES = Object.freeze([
  'station', 'station',
  'lift', 'lift', 'lift',
  'crest',
  'drop', 'drop', 'drop',
  'boost',
  'loop', 'loop',
  'photo',
  'photoTurn',
  'hills', 'hills', 'hills', 'hills', 'hills',
  'hillsTurn',
  'brake', 'brake', 'brake', 'brake', 'brake', 'brake', 'brake',
  'home',
]);

const ss = (t) => {
  const k = Math.min(1, Math.max(0, t));
  return k * k * (3 - 2 * k);
};
const lerp3 = (a, b, f) => [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
const norm3 = (v) => {
  const n = Math.hypot(v[0], v[1], v[2]) || 1;
  return [v[0] / n, v[1] / n, v[2] / n];
};

/**
 * Contiguous role spans in arc-length space.
 * @param {ReturnType<typeof assembleTrack>} assembly
 * @param {readonly string[]} [roles]
 * @returns {Record<string, {s0: number, s1: number, i0: number, i1: number}>}
 */
export function zonesOf(assembly, roles = ROLES) {
  const zones = {};
  for (let i = 0; i < assembly.pieces.length; i += 1) {
    const role = roles[i];
    const piece = assembly.pieces[i];
    if (zones[role] == null) {
      zones[role] = { s0: piece.s0, s1: piece.s1, i0: i, i1: i };
    } else {
      if (zones[role].i1 !== i - 1) {
        throw new Error(`coaster: role '${role}' is not contiguous in ROLES`);
      }
      zones[role].s1 = piece.s1;
      zones[role].i1 = i;
    }
  }
  return zones;
}

/**
 * Merged arc span of the (adjacent) loop pieces — the roll-unclamp range.
 * @param {ReturnType<typeof assembleTrack>} assembly
 * @returns {{s0: number, s1: number}}
 */
export function loopSpanOf(assembly) {
  const loops = assembly.pieces.filter((piece) => piece.type === 'loop');
  return { s0: loops[0]?.s0 ?? 0, s1: loops[loops.length - 1]?.s1 ?? 0 };
}

/**
 * Loop-vantage blend 0…1 at arc s: 0 (plain chase cam) everywhere except
 * inside the loop span, easing in/out over ROLL_BLEND_LEN — drives the
 * exterior dolly-out that watches the train roll through the loops.
 * @param {{s0: number, s1: number}} span @param {number} s
 * @returns {number}
 */
export function rollBlendAt(span, s) {
  const L = COASTER.ROLL_BLEND_LEN;
  const kIn = ss((s - span.s0) / L);
  const kOut = ss((span.s1 - s) / L);
  return Math.min(kIn, kOut);
}

/**
 * Deterministic hands-up windows (drops/loops/hills — held input inside
 * gives sparkles + a 'wheee'; entirely optional, no fail).
 * @param {Record<string, {s0: number, s1: number}>} zones
 * @returns {Array<{id: string, s0: number, s1: number}>}
 */
export function handsUpWindows(zones) {
  return [
    { id: 'drop', s0: zones.drop.s0, s1: zones.boost.s1 },
    // the loop window starts past the loop piece's 2-unit flat entry
    { id: 'loop', s0: zones.loop.s0 + 2, s1: zones.photo.s1 },
    { id: 'hills', s0: zones.hills.s0, s1: zones.hills.s1 },
  ];
}

/**
 * Arc-keyed cue list (fires once each, in order — the self-driven
 * sequencer's caption/sfx track; the view maps cue ids to sfx).
 * @param {Record<string, {s0: number, s1: number}>} zones
 * @param {number} photoS
 * @returns {Array<{id: string, s: number, captionKey: string}>}
 */
export function buildCues(zones, photoS) {
  return [
    { id: 'lift', s: zones.lift.s0, captionKey: 'park.coaster.lift' },
    { id: 'drop', s: zones.drop.s0 - 0.6, captionKey: 'park.coaster.drop' },
    { id: 'loop', s: zones.loop.s0 - 1.5, captionKey: 'park.coaster.loop' },
    { id: 'photo', s: photoS - COASTER.PHOTO_LEAD, captionKey: 'park.coaster.photo' },
    { id: 'hills', s: zones.hills.s0, captionKey: 'park.coaster.hills' },
    { id: 'brake', s: zones.brake.s0 + 4, captionKey: 'park.coaster.brake' },
  ];
}

/**
 * Reduced-motion static shots (the POV NEVER rides the loop): contiguous
 * arc windows covering the whole circuit, each with a fixed camera. The
 * train still runs the same simulation — only the camera is static.
 * @param {ReturnType<typeof assembleTrack>} assembly
 * @returns {Array<{id: string, s0: number, s1: number, cam: number[], look: number[]}>}
 */
export function staticShots(assembly) {
  const zones = zonesOf(assembly);
  const span = loopSpanOf(assembly);
  const side = (s, out, up) => {
    const smp = pointAt(assembly, s);
    // side vector = worldUp × tangent (horizontal, right-handed)
    const sv = norm3([smp.t[2], 0, -smp.t[0]]);
    return [smp.p[0] + sv[0] * out, smp.p[1] + up, smp.p[2] + sv[2] * out];
  };
  const at = (s, dy = 0) => {
    const smp = pointAt(assembly, s);
    return [smp.p[0], smp.p[1] + dy, smp.p[2]];
  };
  const loopMid = (span.s0 + span.s1) / 2;
  // boarding shot: tangent-anchored front-quarter framing of the train at
  // s = 0 (a plain side() shot pushes Gooby out of the narrow portrait FOV)
  const p0 = pointAt(assembly, 0);
  const sv0 = norm3([p0.t[2], 0, -p0.t[0]]);
  const C = COASTER;
  return [
    {
      id: 'station', s0: 0, s1: zones.lift.s0,
      cam: [
        p0.p[0] + sv0[0] * C.SHOT_SIDE - p0.t[0] * C.SHOT_BACK,
        p0.p[1] + C.SHOT_UP,
        p0.p[2] + sv0[2] * C.SHOT_SIDE - p0.t[2] * C.SHOT_BACK,
      ],
      look: [
        p0.p[0] + p0.t[0] * C.SHOT_LOOK_AHEAD,
        p0.p[1] + C.SHOT_LOOK_UP,
        p0.p[2] + p0.t[2] * C.SHOT_LOOK_AHEAD,
      ],
    },
    {
      id: 'lift', s0: zones.lift.s0, s1: zones.drop.s0,
      cam: side(zones.lift.s0 + 1, 6, 1.4), look: at(zones.crest.s0, 0.6),
    },
    {
      id: 'valley', s0: zones.drop.s0, s1: zones.hills.s0,
      cam: side(loopMid, 12, 2.6), look: at(loopMid, 1.7),
    },
    {
      id: 'hills', s0: zones.hills.s0, s1: zones.brake.s0,
      cam: side(zones.hills.s0 + 8, 8, 2.4), look: at(zones.hills.s0 + 10, 0.4),
    },
    {
      id: 'finale', s0: zones.brake.s0, s1: assembly.totalLen,
      cam: side(assembly.totalLen - 3, 7, 2.6), look: at(assembly.totalLen - 4, 0.4),
    },
  ];
}

/**
 * The active static shot for arc s (boarding = the station shot).
 * @param {ReturnType<typeof staticShots>} shots @param {number} s
 * @returns {{id: string, cam: number[], look: number[]}}
 */
export function shotAt(shots, s) {
  for (const shot of shots) {
    if (s < shot.s1) return shot;
  }
  return shots[shots.length - 1];
}

/**
 * Create the ride state (deterministic — no rng anywhere).
 * @param {{reducedMotion?: boolean}} [opts]
 * @returns {object} ride
 */
export function createRide(opts = {}) {
  const assembly = assembleTrack(LAYOUT);
  const zones = zonesOf(assembly);
  const photoZone = zones.photo;
  const photoS = photoZone.s0 + (photoZone.s1 - photoZone.s0) * COASTER.PHOTO_FRACTION;
  return {
    assembly,
    zones,
    loopSpan: loopSpanOf(assembly),
    windows: handsUpWindows(zones),
    cues: buildCues(zones, photoS),
    shots: staticShots(assembly),
    photoS,
    reducedMotion: opts.reducedMotion === true,
    phase: 'boarding', // 'boarding' → 'riding' → 'done'
    boardT: 0, //  boarding-pause clock
    t: 0, //       total seconds since createRide (watchdog clock)
    rideT: 0, //   seconds since departure (camera blend clock)
    s: 0, //       train front-cart arc position (monotonic, no wrap)
    v: 0, //       train speed (track units/s)
    cueIdx: 0,
    photoFired: false,
    skipped: false,
    activeWindow: null,
    heldSec: 0,
    sparkleAcc: 0,
  };
}

/** Role of the zone containing arc s (clamped into the circuit). */
function roleAtS(ride, s) {
  const sm = Math.min(Math.max(0, s), ride.assembly.totalLen - 1e-9);
  for (const piece of ride.assembly.pieces) {
    if (sm >= piece.s0 && sm < piece.s1) return ROLES[piece.index];
  }
  return 'home';
}

/** Spline grade dy/ds at arc s (central difference, wraps). */
function gradeAt(assembly, s) {
  const h = COASTER.GRADE_H;
  const a = pointAt(assembly, s - h);
  const b = pointAt(assembly, s + h);
  return (b.p[1] - a.p[1]) / (2 * h);
}

/** v += clamp(target − v, ±rate·dt) — the zone-target approach step. */
function approach(v, target, rate, dt) {
  const dv = target - v;
  const cap = rate * dt;
  return v + Math.max(-cap, Math.min(cap, dv));
}

/** One fixed integration substep (dt ≤ MAX_SUBSTEP). */
function substep(ride, dt, holding, events) {
  const C = COASTER;
  const role = roleAtS(ride, ride.s);

  // --- speed by zone ---
  if (role === 'station') {
    ride.v = approach(ride.v, C.DEPART_SPEED, C.DEPART_ACCEL, dt);
  } else if (role === 'lift') {
    ride.v = approach(ride.v, C.LIFT_SPEED, C.APPROACH_RATE, dt);
  } else if (role === 'crest') {
    ride.v = approach(ride.v, C.CREST_SPEED, C.APPROACH_RATE, dt);
  } else if (role === 'boost') {
    ride.v = Math.min(C.BOOST_SPEED, ride.v + C.BOOST_ACCEL * dt);
  } else if (role === 'brake') {
    ride.v = Math.max(C.BRAKE_TARGET, ride.v - C.BRAKE_DECEL * dt);
  } else if (role === 'home') {
    const remaining = ride.assembly.totalLen - ride.s;
    const easeTarget = remaining < C.END_EASE_LEN
      ? Math.max(C.END_MIN_V, C.STATION_SPEED * (remaining / C.END_EASE_LEN))
      : C.STATION_SPEED;
    ride.v = Math.min(approach(ride.v, C.STATION_SPEED, C.APPROACH_RATE, dt), Math.max(easeTarget, C.END_MIN_V));
  } else {
    // free track (drop/loop/photo/photoTurn/hills/hillsTurn): energy model
    ride.v += (-C.G * gradeAt(ride.assembly, ride.s) - C.FRICTION * ride.v) * dt;
    ride.v = Math.max(C.VMIN_RUN, ride.v);
  }
  ride.v = Math.min(C.VMAX, ride.v);

  // --- advance (monotonic — the circuit is ridden exactly once) ---
  ride.s += ride.v * dt;
  ride.rideT += dt;

  // --- cues (fire once, in order) ---
  while (ride.cueIdx < ride.cues.length && ride.s >= ride.cues[ride.cueIdx].s) {
    const cue = ride.cues[ride.cueIdx];
    ride.cueIdx += 1;
    events.push({ type: 'cue', id: cue.id, captionKey: cue.captionKey });
  }

  // --- photo flash point ---
  if (!ride.photoFired && ride.s >= ride.photoS) {
    ride.photoFired = true;
    events.push({ type: 'photo' });
  }

  // --- hands-up windows (optional delight — no fail) ---
  const win = ride.windows.find((w) => ride.s >= w.s0 && ride.s < w.s1) ?? null;
  if (win !== ride.activeWindow) {
    if (ride.activeWindow) {
      if (ride.heldSec >= COASTER.WHEEE_MIN_SEC) events.push({ type: 'wheee', id: ride.activeWindow.id });
      events.push({ type: 'windowExit', id: ride.activeWindow.id });
    }
    ride.activeWindow = win;
    ride.heldSec = 0;
    ride.sparkleAcc = 0;
    if (win) events.push({ type: 'windowEnter', id: win.id });
  }
  if (win && holding) {
    ride.heldSec += dt;
    ride.sparkleAcc += dt;
    while (ride.sparkleAcc >= COASTER.HANDS_SPARKLE_EVERY) {
      ride.sparkleAcc -= COASTER.HANDS_SPARKLE_EVERY;
      events.push({ type: 'sparkle' });
    }
  }

  // --- arrival ---
  if (ride.assembly.totalLen - ride.s <= C.END_STOP_EPS) {
    ride.s = ride.assembly.totalLen;
    ride.v = 0;
    ride.phase = 'done';
    events.push({ type: 'cue', id: 'done', captionKey: 'park.coaster.done' });
    events.push({ type: 'arrived' });
  }
}

/**
 * Advance the ride by dt (internally sub-stepped, deterministic).
 * @param {object} ride
 * @param {number} dt seconds
 * @param {{holding?: boolean}} [input] hold-to-hands-up state
 * @returns {Array<object>} events emitted during this step
 */
export function stepRide(ride, dt, input = {}) {
  const events = [];
  if (ride.phase === 'done') return events;
  const holding = input.holding === true;
  ride.t += dt;

  if (ride.phase === 'boarding') {
    const before = ride.boardT ?? 0;
    ride.boardT = before + dt;
    if (before === 0) events.push({ type: 'cue', id: 'board', captionKey: 'park.coaster.board' });
    if (ride.boardT >= COASTER.BOARD_SEC) {
      ride.phase = 'riding';
      events.push({ type: 'depart' });
    }
    return events;
  }

  // watchdog: the ride can NEVER trap the player (cutscene.js discipline)
  if (ride.t > COASTER.WATCHDOG_SEC) {
    ride.s = ride.assembly.totalLen;
    ride.v = 0;
    ride.phase = 'done';
    events.push({ type: 'watchdog' });
    events.push({ type: 'cue', id: 'done', captionKey: 'park.coaster.done' });
    events.push({ type: 'arrived' });
    return events;
  }

  let remaining = Math.min(dt, 0.25);
  while (remaining > 1e-9 && ride.phase === 'riding') {
    const h = Math.min(COASTER.MAX_SUBSTEP, remaining);
    remaining -= h;
    substep(ride, h, holding, events);
  }
  return events;
}

/**
 * Hold-to-skip target: jump straight to the brake run (keepOnSkip
 * semantics — the arrival path still runs, the photo is skipped).
 * @param {object} ride
 * @returns {Array<object>} events ([] when there is nothing to skip)
 */
export function skipRide(ride) {
  const brakeS0 = ride.zones.brake.s0;
  if (ride.phase === 'done' || (ride.phase === 'riding' && ride.s >= brakeS0)) return [];
  const events = [];
  if (ride.activeWindow) {
    events.push({ type: 'windowExit', id: ride.activeWindow.id });
    ride.activeWindow = null;
    ride.heldSec = 0;
  }
  ride.phase = 'riding';
  ride.s = brakeS0;
  ride.v = COASTER.SKIP_ENTRY_SPEED;
  ride.photoFired = true; // skipping skips the souvenir photo too
  ride.skipped = true;
  while (ride.cueIdx < ride.cues.length && ride.cues[ride.cueIdx].s < brakeS0) ride.cueIdx += 1;
  events.push({ type: 'skipped' });
  return events;
}

/**
 * Train cart pose at arc s: position + orthonormal (tangent, up) frame.
 * @param {ReturnType<typeof assembleTrack>} assembly @param {number} s
 * @returns {{p: number[], t: number[], up: number[]}}
 */
export function cartPoseAt(assembly, s) {
  return pointAt(assembly, s);
}

/**
 * Camera pose for the current ride state. Normal mode: world-up chase cam
 * glued to the spline (roll is ALWAYS clamped — the camera never inverts);
 * through the loop span it dollies out to the exterior valley vantage and
 * tracks the train through both inversions (see LOOP_TRACK_LERP — the
 * controlled roll is the TRAIN's, watched from outside); the station shot
 * blends into the chase over CAM_BLEND_SEC after departure (continuous —
 * no cuts). Reduced motion: the active static shot (hard cuts between
 * shots, zero roll, never anywhere near the loop POV).
 * @param {object} ride
 * @returns {{p: number[], look: number[], up: number[], fov01: number}}
 */
export function cameraPose(ride) {
  const C = COASTER;
  if (ride.reducedMotion) {
    const shot = shotAt(ride.shots, ride.s);
    return { p: [...shot.cam], look: [...shot.look], up: [0, 1, 0], fov01: 0 };
  }
  const pose = pointAt(ride.assembly, ride.s);
  let p = [
    pose.p[0] - pose.t[0] * C.CAM_BACK,
    pose.p[1] - pose.t[1] * C.CAM_BACK + C.CAM_UP,
    pose.p[2] - pose.t[2] * C.CAM_BACK,
  ];
  let look = [
    pose.p[0] + pose.t[0] * C.CAM_LOOKAHEAD,
    pose.p[1] + pose.t[1] * C.CAM_LOOKAHEAD + C.CAM_LOOK_UP,
    pose.p[2] + pose.t[2] * C.CAM_LOOKAHEAD,
  ];
  // loop beat: smooth dolly-out to the exterior vantage, tracking the cart
  const blend = rollBlendAt(ride.loopSpan, ride.s);
  if (blend > 0) {
    const shot = shotAt(ride.shots, (ride.loopSpan.s0 + ride.loopSpan.s1) / 2);
    const track = lerp3(shot.look, pose.p, C.LOOP_TRACK_LERP);
    p = lerp3(p, shot.cam, blend);
    look = lerp3(look, track, blend);
  }
  // boarding + departure: ease out of the station shot into the chase cam
  const k = ride.phase === 'boarding' ? 0 : Math.min(1, ride.rideT / C.CAM_BLEND_SEC);
  if (k < 1) {
    const shot = ride.shots[0];
    p = lerp3(shot.cam, p, ss(k));
    look = lerp3(shot.look, look, ss(k));
  }
  return { p, look, up: [0, 1, 0], fov01: Math.min(1, ride.v / C.VMAX) };
}

/**
 * Headless full-ride simulation (test + duration-tuning surface — the
 * §G5.4-style cert sim): fixed-rate stepping with an optional hold policy.
 * @param {{reducedMotion?: boolean, hz?: number,
 *   holdPolicy?: (ride: object) => boolean, maxSec?: number}} [opts]
 * @returns {{durationSec: number, boardingSec: number, maxV: number,
 *   minVRiding: number, events: Array<object>, photoFired: boolean,
 *   arrived: boolean}}
 */
export function simulateRide(opts = {}) {
  const ride = createRide({ reducedMotion: opts.reducedMotion });
  const dt = 1 / (opts.hz ?? 60);
  const maxSec = opts.maxSec ?? 180;
  const events = [];
  let maxV = 0;
  let minVRiding = Infinity;
  let departAt = 0;
  while (ride.phase !== 'done' && ride.t < maxSec) {
    const holding = opts.holdPolicy ? opts.holdPolicy(ride) : false;
    const stepEvents = stepRide(ride, dt, { holding });
    for (const event of stepEvents) {
      if (event.type === 'depart') departAt = ride.t;
      events.push(event);
    }
    if (ride.phase === 'riding') {
      maxV = Math.max(maxV, ride.v);
      // min-speed watch starts past the station departure ramp (v grows
      // from 0 there by design — "never stalls" is about the circuit)
      if (ride.rideT > 3) minVRiding = Math.min(minVRiding, ride.v);
    }
  }
  return {
    durationSec: ride.t - departAt,
    boardingSec: departAt,
    maxV,
    minVRiding,
    events,
    photoFired: ride.photoFired,
    arrived: ride.phase === 'done',
  };
}
