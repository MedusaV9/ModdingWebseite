// Schneckenpost (Snail Mail) — pure path/round logic (PLAN6 Wave C, agent C2;
// concept PLAN5-GAMES-IDEEN §6). No three.js/DOM imports so `node --test`
// runs this headlessly (§B rule); the game module (snailMail.js) imports from
// here. Mechanic: a PATH-DRAWING game — the player draws a delivery path with
// their finger from the post box to the glowing target house/burrow, then the
// courier snail follows the drawn path at constant (arc-length) speed.
// Puddles must be steered around: touching one sends the snail into its shell
// for 2 s and forfeits the dry bonus (Endlos: the 3rd wet delivery ends the
// run). Flowers along the way are picked for bonus points.
//
// Spline toolkit REUSED from goobyWelt.logic.js (catmullRom / dist3 /
// buildTrack — verified exports, imported not copied): drawn points become
// Catmull-Rom waypoints, buildTrack arc-length-parameterizes them, and the
// resampled polyline is what the snail walks and what puddle/flower corridor
// checks run against.
//
// Frozen V6 interface contract (PLAN6 §C2): coin row 4/4/25 → capScore 100,
// Schwer-Ziel 80, unlock L6, energy 8, 60 s, controls invertible:false
// (§G2.1 rule 4 — positional path input). Scoring: delivery +4, dry-delivery
// bonus +2, flower pickup +1.

import { catmullRom, dist3, buildTrack } from './goobyWelt.logic.js';

// The toolkit import is load-bearing for smoothPath (buildTrack/dist3);
// catmullRom is re-exported so the view can preview-smooth partial strokes
// with the exact same basis the track uses.
export { catmullRom, dist3, buildTrack };

/** Binding contract numbers + C2 tuning (field, kinematics, cadence, bot). */
export const SNAIL = Object.freeze({
  /** Round length (s) — Leicht gets +20 % via durationMult. */
  DURATION_SEC: 60,
  // --- the garden field (logic space; the view scales the diorama to fit) ---
  FIELD_HALF_W: 2.2,
  FIELD_Y_MIN: -2.8,
  FIELD_Y_MAX: 2.8,
  /** Post box (path start anchor). */
  POST_X: 0,
  POST_Y: -2.35,
  /** House/burrow band along the top of the garden. */
  HOUSE_SLOTS_X: Object.freeze([-1.5, 0, 1.5]),
  HOUSE_JITTER_X: 0.22,
  HOUSE_Y_MIN: 1.75,
  HOUSE_Y_MAX: 2.4,
  /** Door anchor sits this far below the house center (delivery point). */
  DOOR_OFFSET_Y: 0.32,
  // --- drawn-path sampling / snail follow kinematics ---
  /** Cruise speed (world units/s, arc-length constant — difficulty-scaled). */
  SPEED: 2.1,
  /** Ease-in/out ramp distance at both path ends (wu). */
  SPEED_EASE_DIST: 0.45,
  /** Speed floor inside the ease ramps (fraction of cruise). */
  SPEED_MIN_FRAC: 0.4,
  /** Corridor half-width of the snail body for puddle collision (wu). */
  SNAIL_RADIUS: 0.16,
  /** Arc step of the resampled waypoint polyline (wu). */
  RESAMPLE_STEP: 0.22,
  /** Raw pointer points closer than this are dropped before smoothing (wu). */
  MIN_INPUT_SPACING: 0.12,
  /** A drawn path must BEGIN within this radius of the post box (wu). */
  START_RADIUS: 0.8,
  /** … and END within this radius of the target door (wu). */
  DELIVER_RADIUS: 0.55,
  /** Hard cap on raw input points per stroke (bounded memory). */
  MAX_INPUT_POINTS: 160,
  // --- puddles ---
  PUDDLE_R_MIN: 0.34,
  PUDDLE_R_MAX: 0.5,
  /** Effective-radius multiplier — the §G5.3 "edge forgiveness" knob. */
  PUDDLE_EDGE: 1,
  PUDDLES_START: 2,
  PUDDLES_MAX: 5,
  /** One more puddle every N delivered rounds. */
  PUDDLE_RAMP_EVERY: 2,
  PUDDLE_Y_MIN: -1.7,
  PUDDLE_Y_MAX: 1.15,
  /** Min edge-to-edge clearance between puddles (a snail lane always fits). */
  PUDDLE_GAP: 0.45,
  /** Puddles keep this distance from the post box / house doors (wu). */
  PUDDLE_KEEPOUT: 0.85,
  // --- flowers (bonus pickups seeded near the direct delivery line) ---
  FLOWERS_PER_ROUND: 3,
  FLOWER_PICK_RADIUS: 0.42,
  FLOWER_LANE_OFFSET: 0.9,
  FLOWER_MIN_SPACING: 0.35,
  // --- scoring (FROZEN interface contract) ---
  DELIVER_PTS: 4,
  DRY_BONUS: 2,
  FLOWER_PTS: 1,
  // --- cadence ---
  /** Shell-retreat pause after touching a puddle (s). */
  RETREAT_SEC: 2,
  /** Celebration beat between deliveries (s). */
  ROUND_BEAT_SEC: 0.55,
  // --- V6 §G5 run flags ---
  ENDLESS: false,
  /** §G5.4 Endlos end-condition: 3 wet (splashed) deliveries. */
  ENDLESS_MAX_SPLASHES: 3,
  // --- generation robustness ---
  GEN_MAX_TRIES: 40,
  ROUTE_CLEARANCE: 0.14,
  ROUTE_DETOUR_PAD: 0.34,
  ROUTE_MAX_PASSES: 6,
  ROUTE_SAMPLE_STEP: 0.1,
  // --- deterministic certification bot ---
  BOT_DRAW_SEC: 1.1,
  BOT_WET_RATE: 0.08,
  BOT_TIME_CAP_SEC: 600,
});

/** V6 timed-arena mode rows (§G5.3 family: speed/duration/edge margins). */
export const SNAIL_DIFFICULTY = Object.freeze({
  easy: Object.freeze({ speedMult: 0.85, durationMult: 1.2, puddleEdge: 0.85, drawSec: 1.15, botWet: 0.03 }),
  hard: Object.freeze({ speedMult: 1.2, durationMult: 1, puddleEdge: 1.12, drawSec: 0.95, botWet: 0.3 }),
  endless: Object.freeze({ speedMult: 1.2, durationMult: 1, puddleEdge: 1.12, drawSec: 0.95, botWet: 0.3 }),
});

/** Derive a frozen tune; normal returns the exact Mittel object (§G5.3). */
export function applyDifficulty(tune = SNAIL, mode = 'normal') {
  if (mode === 'normal' || !Object.hasOwn(SNAIL_DIFFICULTY, mode)) return tune;
  const row = SNAIL_DIFFICULTY[mode];
  return Object.freeze({
    ...tune,
    DURATION_SEC: tune.DURATION_SEC * row.durationMult,
    SPEED: tune.SPEED * row.speedMult,
    PUDDLE_EDGE: row.puddleEdge,
    BOT_DRAW_SEC: row.drawSec,
    BOT_WET_RATE: row.botWet,
    ENDLESS: mode === 'endless',
  });
}

/** @param {number} v @param {number} lo @param {number} hi */
function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v));
}

/** @param {{x:number,y:number}} a @param {{x:number,y:number}} b */
function dist2(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

/** Puddle count ramps 2 → 5 as rounds are delivered ("Runden werden größer"). */
export function puddlesForRound(round, tune = SNAIL) {
  const extra = Math.floor(Math.max(0, round) / tune.PUDDLE_RAMP_EVERY);
  return Math.min(tune.PUDDLES_MAX, tune.PUDDLES_START + extra);
}

/** Delivery anchor of a house/burrow (the spot paths must reach). */
export function doorOf(house, tune = SNAIL) {
  return { x: house.x, y: house.y - tune.DOOR_OFFSET_Y };
}

/**
 * Effective puddle radius for collision — the visual radius scaled by the
 * difficulty edge knob plus the snail's own body radius.
 * @param {{r: number}} puddle
 * @param {object} [tune]
 * @returns {number}
 */
export function puddleEffR(puddle, tune = SNAIL) {
  return puddle.r * tune.PUDDLE_EDGE + tune.SNAIL_RADIUS;
}

/**
 * Puddle containing the point, or −1. Strict `<` so the exact edge is safe
 * (edge-forgiveness tests pin this).
 * @param {number} x @param {number} y
 * @param {ReadonlyArray<{x:number,y:number,r:number}>} puddles
 * @param {object} [tune]
 * @returns {number} puddle index or −1
 */
export function puddleHitAt(x, y, puddles, tune = SNAIL) {
  for (let i = 0; i < puddles.length; i += 1) {
    const p = puddles[i];
    if (Math.hypot(x - p.x, y - p.y) < puddleEffR(p, tune)) return i;
  }
  return -1;
}

/** True when every waypoint of a resampled path is clear of every puddle. */
export function pathClear(pts, puddles, tune = SNAIL) {
  for (const pt of pts) {
    if (puddleHitAt(pt.x, pt.y, puddles, tune) >= 0) return false;
  }
  return true;
}

/**
 * Smooth + arc-length-resample a drawn stroke via the goobyWelt spline
 * toolkit: dedupe raw points (MIN_INPUT_SPACING), feed them as Catmull-Rom
 * waypoints into buildTrack, then resample at RESAMPLE_STEP. Deterministic:
 * identical input produces an identical path object.
 * @param {ReadonlyArray<{x:number,y:number}>} rawPts drawn pointer points
 * @param {object} [tune]
 * @returns {{pts: {x:number,y:number}[], cum: number[], length: number}|null}
 *   null when fewer than 2 distinct points survive the spacing filter
 */
export function smoothPath(rawPts, tune = SNAIL) {
  /** @type {[number, number, number][]} */
  const waypoints = [];
  const capped = rawPts.length > tune.MAX_INPUT_POINTS
    ? rawPts.slice(0, tune.MAX_INPUT_POINTS)
    : rawPts;
  for (const p of capped) {
    const v = [p.x, p.y, 0];
    if (waypoints.length === 0 || dist3(waypoints[waypoints.length - 1], v) >= tune.MIN_INPUT_SPACING) {
      waypoints.push(v);
    }
  }
  // Always keep the true stroke end so the delivery check sees the real tip.
  if (capped.length >= 2) {
    const last = capped[capped.length - 1];
    const tail = waypoints[waypoints.length - 1];
    if (dist3(tail, [last.x, last.y, 0]) > 1e-6) {
      if (dist3(tail, [last.x, last.y, 0]) < tune.MIN_INPUT_SPACING && waypoints.length > 1) {
        waypoints[waypoints.length - 1] = [last.x, last.y, 0];
      } else {
        waypoints.push([last.x, last.y, 0]);
      }
    }
  }
  if (waypoints.length < 2) return null;
  const track = buildTrack({
    waypoints,
    corridor: new Array(waypoints.length - 1).fill(1),
  });
  const n = Math.max(2, Math.ceil(track.length / tune.RESAMPLE_STEP) + 1);
  const pts = [];
  const cum = [];
  let prev = null;
  let acc = 0;
  for (let i = 0; i < n; i += 1) {
    const pos = track.posAt((track.length * i) / (n - 1));
    if (prev) acc += dist3(prev, pos);
    pts.push({ x: pos[0], y: pos[1] });
    cum.push(acc);
    prev = pos;
  }
  return Object.freeze({ pts: Object.freeze(pts), cum: Object.freeze(cum), length: acc });
}

/**
 * Snail speed at arc position s: constant cruise with a gentle ease-in/out
 * ramp at both path ends (never exceeds cruise, never stalls below the
 * SPEED_MIN_FRAC floor — the run always terminates).
 * @param {number} s @param {number} length @param {object} [tune]
 * @returns {number} wu/s
 */
export function speedAt(s, length, tune = SNAIL) {
  const ease = Math.min(tune.SPEED_EASE_DIST, length * 0.25);
  let k = 1;
  if (ease > 1e-6) {
    const edge = Math.min(Math.max(0, s), Math.max(0, length - s));
    k = clamp(edge / ease, 0, 1);
  }
  return tune.SPEED * (tune.SPEED_MIN_FRAC + (1 - tune.SPEED_MIN_FRAC) * k);
}

/** Advance the follow arc position by dt (clamped to the path end). */
export function advanceArc(s, dt, length, tune = SNAIL) {
  return Math.min(length, s + speedAt(s, length, tune) * Math.max(0, dt));
}

/**
 * Pose on the resampled path at arc distance s, written into `out` (the view
 * calls this per frame — no allocation). Angle is the segment direction.
 * @param {{pts: {x:number,y:number}[], cum: number[], length: number}} path
 * @param {number} s
 * @param {{x:number,y:number,angle:number}} out mutated + returned
 */
export function followInto(path, s, out) {
  const { pts, cum } = path;
  const c = clamp(s, 0, path.length);
  // binary search: greatest index with cum[i] <= c
  let lo = 0;
  let hi = cum.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (cum[mid] <= c) lo = mid;
    else hi = mid - 1;
  }
  const i = Math.min(lo, pts.length - 2);
  const span = cum[i + 1] - cum[i];
  const f = span > 1e-9 ? (c - cum[i]) / span : 0;
  const a = pts[i];
  const b = pts[i + 1];
  out.x = a.x + (b.x - a.x) * f;
  out.y = a.y + (b.y - a.y) * f;
  out.angle = Math.atan2(b.y - a.y, b.x - a.x);
  return out;
}

/** Allocating convenience wrapper around followInto (tests / bot). */
export function followAt(path, s) {
  return followInto(path, s, { x: 0, y: 0, angle: 0 });
}

/**
 * Flower indices picked by a path (any waypoint within FLOWER_PICK_RADIUS).
 * @param {{pts: {x:number,y:number}[]}} path
 * @param {ReadonlyArray<{x:number,y:number}>} flowers
 * @param {object} [tune]
 * @returns {number[]} ascending indices
 */
export function flowersOnPath(path, flowers, tune = SNAIL) {
  const picked = [];
  for (let i = 0; i < flowers.length; i += 1) {
    const fl = flowers[i];
    for (const pt of path.pts) {
      if (dist2(pt, fl) <= tune.FLOWER_PICK_RADIUS) {
        picked.push(i);
        break;
      }
    }
  }
  return picked;
}

/** Does a drawn stroke begin close enough to the post box? */
export function startsAtPost(pt, tune = SNAIL) {
  return dist2(pt, { x: tune.POST_X, y: tune.POST_Y }) <= tune.START_RADIUS;
}

/**
 * House whose door the path END reaches (nearest within DELIVER_RADIUS), −1
 * when the stroke ends in the open garden.
 * @param {{pts: {x:number,y:number}[]}} path
 * @param {{houses: ReadonlyArray<{x:number,y:number}>}} level
 * @param {object} [tune]
 * @returns {number}
 */
export function endHouse(path, level, tune = SNAIL) {
  const tip = path.pts[path.pts.length - 1];
  let best = -1;
  let bestD = Infinity;
  for (let i = 0; i < level.houses.length; i += 1) {
    const d = dist2(tip, doorOf(level.houses[i], tune));
    if (d <= tune.DELIVER_RADIUS && d < bestD) {
      best = i;
      bestD = d;
    }
  }
  return best;
}

/** Points for one completed delivery (FROZEN contract: 4 / +2 dry / +1 flower). */
export function deliveryPoints(wet, flowersPicked, tune = SNAIL) {
  return tune.DELIVER_PTS
    + (wet ? 0 : tune.DRY_BONUS)
    + Math.max(0, flowersPicked) * tune.FLOWER_PTS;
}

/** Apply a delta to the score, floored at 0. */
export function applyScore(score, delta) {
  return Math.max(0, score + delta);
}

/** §G5.4 Endlos ends on the third wet (splashed) delivery. */
export function endlessShouldEnd(splashes, tune = SNAIL) {
  return tune.ENDLESS === true && splashes >= tune.ENDLESS_MAX_SPLASHES;
}

// ---------------------------------------------------------------------------
// Level generation (seeded, ALWAYS solvable) + the reference auto-route
// ---------------------------------------------------------------------------

/** First puddle blocked by any straight segment of a polyline, or −1. */
function firstBlocked(pts, puddles, tune) {
  for (let i = 0; i < pts.length - 1; i += 1) {
    const a = pts[i];
    const b = pts[i + 1];
    const len = dist2(a, b);
    const steps = Math.max(1, Math.ceil(len / tune.ROUTE_SAMPLE_STEP));
    for (let k = 0; k <= steps; k += 1) {
      const x = a.x + ((b.x - a.x) * k) / steps;
      const y = a.y + ((b.y - a.y) * k) / steps;
      for (let j = 0; j < puddles.length; j += 1) {
        const p = puddles[j];
        if (Math.hypot(x - p.x, y - p.y) < puddleEffR(p, tune) + tune.ROUTE_CLEARANCE) {
          return { seg: i, puddle: j };
        }
      }
    }
  }
  return null;
}

/**
 * Reference route from the post box to the target door: a straight line that
 * detours around blocking puddles (perpendicular offset waypoints). Returns
 * the raw polyline AND its smoothed resample; `ok` guarantees the SMOOTHED
 * path is clear, starts at the post and ends on the target door — i.e. a
 * valid drawable delivery path exists. Also the certification bot's route.
 * @param {{post: {x:number,y:number}, houses: object[], targetIdx: number,
 *   puddles: object[]}} level
 * @param {object} [tune]
 * @returns {{ok: boolean, pts: {x:number,y:number}[],
 *   smooth: ReturnType<typeof smoothPath>}}
 */
export function autoRoute(level, tune = SNAIL) {
  const door = doorOf(level.houses[level.targetIdx], tune);
  const pts = [{ x: level.post.x, y: level.post.y }, { x: door.x, y: door.y }];
  const xLim = tune.FIELD_HALF_W - 0.12;
  for (let pass = 0; pass < tune.ROUTE_MAX_PASSES; pass += 1) {
    const hit = firstBlocked(pts, puddlesOf(level), tune);
    if (!hit) break;
    const p = level.puddles[hit.puddle];
    const a = pts[hit.seg];
    const b = pts[hit.seg + 1];
    // closest point of the segment to the puddle center → push away from it
    const abx = b.x - a.x;
    const aby = b.y - a.y;
    const abLen2 = abx * abx + aby * aby || 1;
    const t = clamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / abLen2, 0, 1);
    const cx = a.x + abx * t;
    const cy = a.y + aby * t;
    let wx = cx - p.x;
    let wy = cy - p.y;
    const wLen = Math.hypot(wx, wy);
    if (wLen < 1e-6) {
      // segment passes exactly through the center — use the left normal
      wx = -aby;
      wy = abx;
      const nLen = Math.hypot(wx, wy) || 1;
      wx /= nLen;
      wy /= nLen;
    } else {
      wx /= wLen;
      wy /= wLen;
    }
    const reach = puddleEffR(p, tune) + tune.ROUTE_CLEARANCE + tune.ROUTE_DETOUR_PAD;
    let dx = clamp(p.x + wx * reach, -xLim, xLim);
    let dy = clamp(p.y + wy * reach, tune.FIELD_Y_MIN + 0.12, tune.FIELD_Y_MAX - 0.12);
    // clamped back into the puddle? mirror to the other side
    if (Math.hypot(dx - p.x, dy - p.y) < reach - 1e-6) {
      dx = clamp(p.x - wx * reach, -xLim, xLim);
      dy = clamp(p.y - wy * reach, tune.FIELD_Y_MIN + 0.12, tune.FIELD_Y_MAX - 0.12);
    }
    pts.splice(hit.seg + 1, 0, { x: dx, y: dy });
  }
  const smooth = smoothPath(pts, tune);
  const ok = smooth != null
    && pathClear(smooth.pts, puddlesOf(level), tune)
    && endHouse(smooth, level, tune) === level.targetIdx;
  return { ok, pts, smooth };
}

/** @param {{puddles: object[]}} level */
function puddlesOf(level) {
  return level.puddles;
}

/**
 * Generate one delivery round from the seeded rng: post box (fixed anchor),
 * 3 candidate houses/burrows along the top, the target pick, ramped puddles
 * and 3 flowers seeded near the direct line. ALWAYS solvable: candidate
 * placements are validated with autoRoute (on the smoothed path) and
 * re-rolled deterministically; every GEN_MAX_TRIES failures one puddle is
 * dropped, and a zero-puddle field is trivially routable — generation can
 * never spin forever.
 * @param {() => number} rng seeded 0..1
 * @param {number} round 0-based delivered-rounds counter
 * @param {object} [tune]
 * @returns {{post: {x:number,y:number}, houses: object[], targetIdx: number,
 *   puddles: {x:number,y:number,r:number}[], flowers: {x:number,y:number}[],
 *   round: number}}
 */
export function generateLevel(rng, round, tune = SNAIL) {
  const post = { x: tune.POST_X, y: tune.POST_Y };
  const kinds = ['house', 'burrow', 'house'];
  const houses = tune.HOUSE_SLOTS_X.map((sx, i) => ({
    x: clamp(sx + (rng() * 2 - 1) * tune.HOUSE_JITTER_X, -tune.FIELD_HALF_W + 0.45, tune.FIELD_HALF_W - 0.45),
    y: tune.HOUSE_Y_MIN + rng() * (tune.HOUSE_Y_MAX - tune.HOUSE_Y_MIN),
    kind: kinds[i],
  }));
  const targetIdx = Math.min(houses.length - 1, Math.floor(rng() * houses.length));
  const door = doorOf(houses[targetIdx], tune);

  let wantPuddles = puddlesForRound(round, tune);
  for (let attempt = 0; ; attempt += 1) {
    if (attempt > 0 && attempt % tune.GEN_MAX_TRIES === 0 && wantPuddles > 0) {
      wantPuddles -= 1; // safety valve — 0 puddles is always routable
    }
    // --- puddles ---
    const puddles = [];
    let placed = true;
    for (let i = 0; i < wantPuddles && placed; i += 1) {
      placed = false;
      for (let roll = 0; roll < 20; roll += 1) {
        const r = tune.PUDDLE_R_MIN + rng() * (tune.PUDDLE_R_MAX - tune.PUDDLE_R_MIN);
        const x = (rng() * 2 - 1) * (tune.FIELD_HALF_W - r - 0.15);
        const y = tune.PUDDLE_Y_MIN + rng() * (tune.PUDDLE_Y_MAX - tune.PUDDLE_Y_MIN);
        if (Math.hypot(x - post.x, y - post.y) < r + tune.PUDDLE_KEEPOUT) continue;
        let clear = true;
        for (const h of houses) {
          const d = doorOf(h, tune);
          if (Math.hypot(x - d.x, y - d.y) < r + tune.PUDDLE_KEEPOUT) {
            clear = false;
            break;
          }
        }
        if (!clear) continue;
        for (const p of puddles) {
          if (Math.hypot(x - p.x, y - p.y) < r + p.r + tune.PUDDLE_GAP) {
            clear = false;
            break;
          }
        }
        if (!clear) continue;
        puddles.push({ x, y, r });
        placed = true;
        break;
      }
    }
    if (!placed) continue;
    // --- flowers near the direct post→door line (pickable rewards) ---
    const flowers = [];
    for (let i = 0; i < tune.FLOWERS_PER_ROUND; i += 1) {
      const frac = 0.28 + (i / Math.max(1, tune.FLOWERS_PER_ROUND - 1)) * 0.5;
      for (let roll = 0; roll < 10; roll += 1) {
        const jitter = (rng() * 2 - 1) * tune.FLOWER_LANE_OFFSET;
        const lx = post.x + (door.x - post.x) * frac;
        const ly = post.y + (door.y - post.y) * frac;
        // lateral offset perpendicular to the direct line
        const dirX = door.x - post.x;
        const dirY = door.y - post.y;
        const dirLen = Math.hypot(dirX, dirY) || 1;
        const x = clamp(lx + (-dirY / dirLen) * jitter, -tune.FIELD_HALF_W + 0.2, tune.FIELD_HALF_W - 0.2);
        const y = clamp(ly + (dirX / dirLen) * jitter, tune.FIELD_Y_MIN + 0.3, tune.FIELD_Y_MAX - 0.6);
        if (puddleHitAt(x, y, puddles, tune) >= 0) continue;
        let spaced = true;
        for (const f of flowers) {
          if (Math.hypot(x - f.x, y - f.y) < tune.FLOWER_MIN_SPACING) {
            spaced = false;
            break;
          }
        }
        if (!spaced) continue;
        flowers.push({ x, y });
        break;
      }
    }
    const level = { post, houses, targetIdx, puddles, flowers, round };
    if (autoRoute(level, tune).ok) return level;
  }
}

// ---------------------------------------------------------------------------
// Deterministic certification bot (§G5.4 adapter: simulateSnailAutoplay(mode, seed))
// ---------------------------------------------------------------------------

/**
 * Deterministic tune-driven certification run: generates real rounds, routes
 * them with autoRoute, integrates the real follow kinematics for travel time
 * and rolls a human-ish wet-slip per delivery (BOT_WET_RATE).
 * @param {'easy'|'normal'|'hard'|'endless'} [mode]
 * @param {number} [seed]
 */
export function simulateSnailAutoplay(mode = 'normal', seed = 1) {
  const tune = applyDifficulty(SNAIL, mode);
  let a = seed >>> 0;
  const rng = () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let x = Math.imul(a ^ (a >>> 15), 1 | a);
    x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) | 0;
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
  let elapsed = 0;
  let score = 0;
  let deliveries = 0;
  let splashes = 0;
  let flowersPicked = 0;
  const limit = tune.ENDLESS ? tune.BOT_TIME_CAP_SEC : tune.DURATION_SEC;
  while (elapsed < limit && !endlessShouldEnd(splashes, tune)) {
    const level = generateLevel(rng, deliveries, tune);
    const route = autoRoute(level, tune);
    const path = route.smooth;
    // integrate the real kinematics for the travel time (dt = 1/30)
    let s = 0;
    let travel = 0;
    while (s < path.length && travel < 60) {
      s = advanceArc(s, 1 / 30, path.length, tune);
      travel += 1 / 30;
    }
    const wet = rng() < tune.BOT_WET_RATE;
    const picked = flowersOnPath(path, level.flowers, tune).length;
    score = applyScore(score, deliveryPoints(wet, picked, tune));
    deliveries += 1;
    flowersPicked += picked;
    if (wet) splashes += 1;
    elapsed += tune.BOT_DRAW_SEC + travel + (wet ? tune.RETREAT_SEC : 0) + tune.ROUND_BEAT_SEC;
  }
  return Object.freeze({ seed, mode, score, deliveries, splashes, flowersPicked, elapsed });
}
