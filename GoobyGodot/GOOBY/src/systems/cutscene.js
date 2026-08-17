// V6/A1 — cutscene director core (PLAN6 Wave A/A1): the PURE sequencing
// engine behind every authored cinematic. NO DOM/three imports — node:test
// drives it directly (test/cutscene.test.js); the DOM/three driver lives in
// ui/cutsceneView.js and binds compiled ops to the real systems (camera,
// Gooby rig, particles, audio, captions).
//
// Architecture (vacation.js/modifierEngine.js precedent):
//   compileScript(script, {reducedMotion}) — validates a data-only script
//     (data/cutscenes.js shapes) into a frozen compiled form, throwing on any
//     malformed op, clamping every duration, defaulting/clamping every
//     tapWait timeout (tapWait can NEVER wait forever), and — under reduced
//     motion — collapsing camera moves and shortening waits.
//   createCutscenePlayer(compiled, hooks, opts) — a tick(dt)-driven state
//     machine: sequence/parallel groups, wait/tapWait steps, first-view
//     hold-to-skip vs replay tap-skip, a WATCHDOG_SEC force-finish, and
//     keepOnSkip ops applied on every skip path so final-state ops always
//     land. The player never touches a clock — the driver feeds dt.
//   defaultSlice()/sliceOf()/markSeenSlice()/hasSeen() — the additive
//     `cutscenes` save slice (V5 vacation.js pattern, NO SAVE.VERSION bump;
//     core/save.js mergeDefaults passes unknown top-level keys through
//     verbatim). The seen map is bounded to CUTSCENE_IDS — junk ids are
//     dropped on every read, so the slice can never grow unbounded.
//
// §E0.1-2: every exact number is a frozen const INSIDE this owning module.

import { CUTSCENE_IDS } from '../data/cutscenes.js';

/** §E0.1-2: the binding cutscene-director numbers — frozen here. */
export const CUTSCENE = Object.freeze({
  /** Hard watchdog: total playback seconds before force-finish (risk #5). */
  WATCHDOG_SEC: 45,
  /** First-view skip: seconds the skip affordance must be HELD. */
  HOLD_SKIP_SEC: 0.6,
  /** Released hold-progress decays at this multiple of the fill rate. */
  HOLD_DECAY_MULT: 2,
  /** tapWait timeout default/floor/ceiling (a tapWait can never block). */
  TAPWAIT_DEFAULT_SEC: 6,
  TAPWAIT_MIN_SEC: 0.5,
  TAPWAIT_MAX_SEC: 12,
  /** Per-step duration ceiling (camera/wait). */
  MAX_STEP_SEC: 10,
  /** Reduced-motion compile: waits shorten to this ceiling. */
  REDUCED_WAIT_MAX_SEC: 0.4,
  /** Group nesting ceiling + total op ceiling (bounded scripts only). */
  MAX_DEPTH: 4,
  MAX_OPS: 64,
  /** Particle burst count ceiling per op. */
  MAX_PARTICLE_COUNT: 24,
});

/** The op vocabulary the compiler accepts (driver binding in cutsceneView). */
export const OP_KINDS = Object.freeze([
  'camera', 'clip', 'emotion', 'particles', 'caption', 'captionClear',
  'sfx', 'prop', 'wait', 'tapWait', 'sequence', 'parallel',
]);

/** Camera moves the view driver implements (data stays declarative). */
export const CAMERA_MOVES = Object.freeze(['pushIn', 'pullBack', 'restore']);

/** Particle types cutscenes may burst — mirrored against gfx/particles.js
 * TYPES by the data-mirror test (source scan — particles.js imports three
 * and must stay out of headless test imports). */
export const CUTSCENE_PARTICLE_TYPES = Object.freeze([
  'sparkles', 'hearts', 'confetti',
]);

/** Prop actions (spawn adds an assets.getModel clone; despawn removes). */
export const PROP_ACTIONS = Object.freeze(['spawn', 'despawn']);

// ---------------------------------------------------------------------------
// Compile
// ---------------------------------------------------------------------------

/**
 * @param {string} msg
 * @param {string} path
 * @returns {Error}
 */
function bad(msg, path) {
  return new Error(`cutscene compile: ${msg} at ${path}`);
}

/**
 * @param {*} v
 * @param {number} fallback
 * @param {number} max
 * @returns {number} finite, clamped to [0, max]
 */
function clampSec(v, fallback, max) {
  const n = Number(v);
  const val = Number.isFinite(n) ? n : fallback;
  return Math.min(max, Math.max(0, val));
}

/**
 * @param {*} v
 * @returns {boolean} true only for a non-empty string
 */
function isNonEmptyString(v) {
  return typeof v === 'string' && v.length > 0;
}

/**
 * Validate + normalize ONE step (recursing into groups).
 * @param {object} step raw step from the script
 * @param {{reducedMotion: boolean}} opts
 * @param {string} path error-message breadcrumb
 * @param {number} depth group nesting depth
 * @param {{ops: number}} budget shared op counter
 * @returns {object} frozen normalized step
 */
function compileStep(step, opts, path, depth, budget) {
  if (step == null || typeof step !== 'object' || Array.isArray(step)) {
    throw bad('step must be an object', path);
  }
  budget.ops += 1;
  if (budget.ops > CUTSCENE.MAX_OPS) throw bad(`more than ${CUTSCENE.MAX_OPS} ops`, path);
  const op = step.op;
  if (!OP_KINDS.includes(op)) throw bad(`unknown op '${op}'`, path);
  const keepOnSkip = step.keepOnSkip === true;
  /** @type {object} */
  const out = { op, keepOnSkip };

  switch (op) {
    case 'camera': {
      if (!CAMERA_MOVES.includes(step.move)) throw bad(`unknown camera move '${step.move}'`, path);
      out.move = step.move;
      // Reduced motion collapses camera dollies to an instant cut.
      out.duration = opts.reducedMotion
        ? 0
        : clampSec(step.duration, 1, CUTSCENE.MAX_STEP_SEC);
      break;
    }
    case 'clip': {
      if (!isNonEmptyString(step.clip)) throw bad('clip needs a clip id', path);
      out.clip = step.clip;
      break;
    }
    case 'emotion': {
      if (!isNonEmptyString(step.emotion)) throw bad('emotion needs an emotion id', path);
      out.emotion = step.emotion;
      break;
    }
    case 'particles': {
      if (!CUTSCENE_PARTICLE_TYPES.includes(step.type)) {
        throw bad(`unknown particle type '${step.type}'`, path);
      }
      out.type = step.type;
      const count = Math.floor(Number(step.count));
      out.count = Number.isFinite(count) && count > 0
        ? Math.min(CUTSCENE.MAX_PARTICLE_COUNT, count)
        : 8;
      if (step.anchor != null) {
        if (!isNonEmptyString(step.anchor)) throw bad('particles anchor must be a string', path);
        out.anchor = step.anchor;
      }
      break;
    }
    case 'caption': {
      if (!isNonEmptyString(step.key)) throw bad('caption needs a t() key', path);
      out.key = step.key;
      break;
    }
    case 'captionClear':
      break;
    case 'sfx': {
      if (!isNonEmptyString(step.sfx)) throw bad('sfx needs an sfxMap id', path);
      out.sfx = step.sfx;
      break;
    }
    case 'prop': {
      if (!PROP_ACTIONS.includes(step.action)) throw bad(`unknown prop action '${step.action}'`, path);
      if (!isNonEmptyString(step.propId)) throw bad('prop needs a propId', path);
      out.action = step.action;
      out.propId = step.propId;
      if (step.action === 'spawn') {
        if (!isNonEmptyString(step.model)) throw bad('prop spawn needs a model asset key', path);
        out.model = step.model;
        if (step.anchor != null) {
          if (!isNonEmptyString(step.anchor)) throw bad('prop anchor must be a string', path);
          out.anchor = step.anchor;
        }
        if (step.offset != null) {
          const off = step.offset;
          const okOffset = Array.isArray(off) && off.length === 3
            && off.every((n) => Number.isFinite(Number(n)));
          if (!okOffset) throw bad('prop offset must be [x,y,z]', path);
          out.offset = Object.freeze([Number(off[0]), Number(off[1]), Number(off[2])]);
        }
        if (step.scale != null) {
          const s = Number(step.scale);
          if (!Number.isFinite(s) || s <= 0) throw bad('prop scale must be > 0', path);
          out.scale = Math.min(10, s);
        }
      }
      break;
    }
    case 'wait': {
      const dur = clampSec(step.duration, 0, CUTSCENE.MAX_STEP_SEC);
      if (!(Number(step.duration) > 0)) throw bad('wait needs duration > 0', path);
      out.duration = opts.reducedMotion
        ? Math.min(dur, CUTSCENE.REDUCED_WAIT_MAX_SEC)
        : dur;
      break;
    }
    case 'tapWait': {
      // The MANDATORY timeout fallback: absent/junk values get the default,
      // and every timeout is clamped so a tapWait can never soft-lock.
      const raw = Number(step.timeout);
      const timeout = Number.isFinite(raw) ? raw : CUTSCENE.TAPWAIT_DEFAULT_SEC;
      out.timeout = Math.min(
        CUTSCENE.TAPWAIT_MAX_SEC,
        Math.max(CUTSCENE.TAPWAIT_MIN_SEC, timeout),
      );
      break;
    }
    case 'sequence':
    case 'parallel': {
      if (depth >= CUTSCENE.MAX_DEPTH) throw bad(`groups nested deeper than ${CUTSCENE.MAX_DEPTH}`, path);
      if (!Array.isArray(step.steps) || step.steps.length === 0) {
        throw bad(`${op} needs a non-empty steps array`, path);
      }
      out.steps = Object.freeze(step.steps.map(
        (child, i) => compileStep(child, opts, `${path}.${op}[${i}]`, depth + 1, budget),
      ));
      break;
    }
    default:
      throw bad(`unhandled op '${op}'`, path);
  }
  return Object.freeze(out);
}

/**
 * Worst-case seconds a compiled step can occupy (tapWait counts its timeout)
 * — the progress denominator, NOT a playback promise.
 * @param {object} step compiled step
 * @returns {number}
 */
export function stepDurationSec(step) {
  switch (step.op) {
    case 'camera': return step.duration;
    case 'wait': return step.duration;
    case 'tapWait': return step.timeout;
    case 'sequence': return step.steps.reduce((sum, s) => sum + stepDurationSec(s), 0);
    case 'parallel': return step.steps.reduce((max, s) => Math.max(max, stepDurationSec(s)), 0);
    default: return 0;
  }
}

/**
 * Validate + normalize a data-only script into the frozen compiled form the
 * player consumes. Throws on ANY malformed input — a cutscene that cannot
 * compile must never start (callers treat the throw as "skip silently").
 * @param {{id: string, steps: object[]}} script data/cutscenes.js shape
 * @param {{reducedMotion?: boolean}} [options]
 * @returns {{id: string, steps: readonly object[], totalSec: number, reducedMotion: boolean}}
 */
export function compileScript(script, options = {}) {
  const reducedMotion = options.reducedMotion === true;
  if (script == null || typeof script !== 'object' || Array.isArray(script)) {
    throw bad('script must be an object', 'root');
  }
  if (!isNonEmptyString(script.id)) throw bad('script needs a string id', 'root');
  if (!Array.isArray(script.steps) || script.steps.length === 0) {
    throw bad('script needs a non-empty steps array', 'root');
  }
  const budget = { ops: 0 };
  const steps = Object.freeze(script.steps.map(
    (step, i) => compileStep(step, { reducedMotion }, `${script.id}[${i}]`, 0, budget),
  ));
  const totalSec = steps.reduce((sum, s) => sum + stepDurationSec(s), 0);
  return Object.freeze({ id: script.id, steps, totalSec, reducedMotion });
}

// ---------------------------------------------------------------------------
// Player
// ---------------------------------------------------------------------------

/** Leaf ops that apply instantly (fire the hook, complete the same tick). */
const INSTANT_OPS = Object.freeze([
  'clip', 'emotion', 'particles', 'caption', 'captionClear', 'sfx', 'prop',
]);

/**
 * @param {object} step compiled step
 * @returns {object} fresh runtime node
 */
function makeNode(step) {
  return {
    step,
    started: false,
    done: false,
    t: 0,
    children: step.steps ? step.steps.map(makeNode) : null,
  };
}

/**
 * The tick(dt)-driven playback state machine. Pure: no clocks, no DOM — the
 * driver calls tick(dt) each frame and receives ops through `hooks.apply`.
 *
 * @param {ReturnType<typeof compileScript>} compiled
 * @param {{apply?: (op: object, info: {skipped: boolean}) => void}} [hooks]
 *   apply() is invoked once per op when it starts; keepOnSkip ops are also
 *   applied (with skipped:true) when a skip/watchdog ends playback early.
 *   Driver errors are contained — a throwing hook never stalls the player.
 * @param {{replay?: boolean}} [opts] replay=true enables instant tap-skip;
 *   first view (replay=false) requires the hold-to-skip gesture.
 * @returns {{
 *   start: () => void,
 *   tick: (dt: number) => void,
 *   tap: () => boolean,
 *   skipTap: () => boolean,
 *   skipHoldStart: () => void,
 *   skipHoldEnd: () => void,
 *   skip: (reason?: string) => void,
 *   cancel: () => void,
 *   getState: () => string,
 *   getProgress: () => number,
 *   getHoldProgress: () => number,
 *   isAwaitingTap: () => boolean,
 *   isReplay: () => boolean,
 *   getFinishReason: () => string|null,
 *   onFinish: (cb: (reason: string) => void) => (() => void),
 * }}
 */
export function createCutscenePlayer(compiled, hooks = {}, opts = {}) {
  const replay = opts.replay === true;
  const root = makeNode(Object.freeze({ op: 'sequence', steps: compiled.steps }));

  let state = 'idle'; // 'idle' | 'playing' | 'done'
  let finishReason = null; // 'completed' | 'skipped' | 'watchdog' | 'cancelled'
  let elapsed = 0;
  let holding = false;
  let holdProgress = 0;
  /** @type {Array<(reason: string) => void>} */
  const finishCbs = [];

  /** Contained hook call — a throwing driver must never wedge playback. */
  function applyOp(step, skipped) {
    try {
      hooks.apply?.(step, { skipped });
    } catch (err) {
      console.warn(`[cutscene] apply('${step.op}') hook failed:`, err);
    }
  }

  /**
   * Walk every op not yet APPLIED (started) in document order and apply the
   * keepOnSkip ones — final-state ops (emotions, restores, unlock sfx) land
   * even when the player skips at second one.
   * @param {object} node
   */
  function applyKeepOnSkip(node) {
    if (node.children) {
      // Group itself carries no side effect; recurse in order.
      for (const child of node.children) applyKeepOnSkip(child);
      return;
    }
    if (!node.started && node.step.keepOnSkip) applyOp(node.step, true);
  }

  /** @param {string} reason */
  function finish(reason) {
    if (state === 'done') return;
    state = 'done';
    finishReason = reason;
    for (const cb of [...finishCbs]) {
      try {
        cb(reason);
      } catch (err) {
        console.warn('[cutscene] onFinish callback failed:', err);
      }
    }
  }

  /** @param {string} reason */
  function skipNow(reason) {
    if (state !== 'playing') return;
    applyKeepOnSkip(root);
    finish(reason);
  }

  /**
   * Start a node (fire its op / activate children). Instant ops complete
   * immediately so a run of them advances deterministically in one tick.
   * @param {object} node
   */
  function startNode(node) {
    node.started = true;
    const step = node.step;
    if (node.children) {
      if (step.op === 'parallel') for (const child of node.children) startNode(child);
      else startNode(node.children[0]); // sequence: first child only
      return;
    }
    applyOp(step, false);
    if (INSTANT_OPS.includes(step.op)) node.done = true;
  }

  /**
   * Advance a started node by dt; marks done when complete.
   * @param {object} node
   * @param {number} dt
   */
  function advanceNode(node, dt) {
    if (node.done) return;
    if (!node.started) startNode(node);
    if (node.done) return;
    const step = node.step;
    if (node.children) {
      if (step.op === 'parallel') {
        for (const child of node.children) advanceNode(child, dt);
        node.done = node.children.every((c) => c.done);
      } else {
        // sequence: pump children until one blocks (instant ops chain freely;
        // leftover time past a duration end is NOT carried into the next
        // step — deterministic, tick-quantized advancement).
        let guard = node.children.length + 1;
        while (guard > 0) {
          guard -= 1;
          const current = node.children.find((c) => !c.done);
          if (!current) {
            node.done = true;
            return;
          }
          advanceNode(current, dt);
          if (!current.done) return; // blocked on a duration/tap step
          dt = 0; // chained follow-ups start this tick but consume no time
        }
      }
      return;
    }
    switch (step.op) {
      case 'camera':
      case 'wait':
        node.t += dt;
        if (node.t >= step.duration) node.done = true;
        break;
      case 'tapWait':
        node.t += dt;
        if (node.t >= step.timeout) node.done = true; // the mandatory fallback
        break;
      default:
        node.done = true; // instant ops finished in startNode
    }
  }

  /**
   * @param {object} node
   * @param {(node: object) => boolean} fn stop walking when fn returns true
   * @returns {boolean}
   */
  function someActive(node, fn) {
    if (node.done || !node.started) return false;
    if (node.children) return node.children.some((c) => someActive(c, fn));
    return fn(node);
  }

  /** Progress numerator: completed seconds across the tree (parallel groups
   * count their SLOWEST lane — children run concurrently, so elapsed group
   * time is the max, matching stepDurationSec's weight). */
  function doneSec(node) {
    const step = node.step;
    if (node.done) return stepDurationSec(step);
    if (node.children) {
      if (step.op === 'parallel') {
        return node.children.reduce((max, c) => Math.max(max, doneSec(c)), 0);
      }
      return node.children.reduce((sum, c) => sum + doneSec(c), 0);
    }
    if (!node.started) return 0;
    return Math.min(node.t, stepDurationSec(step));
  }

  return {
    /** Arm playback (first ops fire on the next tick). */
    start() {
      if (state !== 'idle') return;
      state = 'playing';
    },

    /**
     * Advance playback. dt is clamped defensively so a background-tab frame
     * gap can never leap the watchdog in one call.
     * @param {number} dt seconds since last tick
     */
    tick(dt) {
      if (state !== 'playing') return;
      const step = Math.min(Math.max(Number(dt) || 0, 0), 0.25);
      elapsed += step;

      // hold-to-skip model (first view): fill while held, decay when free.
      if (holding) {
        holdProgress = Math.min(1, holdProgress + step / CUTSCENE.HOLD_SKIP_SEC);
        if (holdProgress >= 1) {
          skipNow('skipped');
          return;
        }
      } else if (holdProgress > 0) {
        holdProgress = Math.max(
          0,
          holdProgress - (step * CUTSCENE.HOLD_DECAY_MULT) / CUTSCENE.HOLD_SKIP_SEC,
        );
      }

      advanceNode(root, step);
      if (root.done) {
        finish('completed');
        return;
      }
      if (elapsed >= CUTSCENE.WATCHDOG_SEC) skipNow('watchdog');
    },

    /**
     * A content tap (anywhere): completes every ACTIVE tapWait.
     * @returns {boolean} true when a tapWait consumed it
     */
    tap() {
      if (state !== 'playing') return false;
      let consumed = false;
      someActive(root, (node) => {
        if (node.step.op === 'tapWait') {
          node.done = true;
          consumed = true;
        }
        return false; // keep walking — parallel groups may hold several
      });
      return consumed;
    },

    /**
     * A tap on the skip affordance: instant skip on replays only (first view
     * requires the hold gesture).
     * @returns {boolean} true when the tap skipped
     */
    skipTap() {
      if (state !== 'playing' || !replay) return false;
      skipNow('skipped');
      return true;
    },

    /** Press the skip affordance (first-view hold gesture). */
    skipHoldStart() {
      if (state !== 'playing') return;
      holding = true;
    },

    /** Release the skip affordance (progress decays via tick). */
    skipHoldEnd() {
      holding = false;
    },

    /** Programmatic skip (dev/emergency) — keepOnSkip ops still apply. */
    skip(reason = 'skipped') {
      skipNow(reason);
    },

    /** Hard abort: NO keepOnSkip application (driver error path only). */
    cancel() {
      finish('cancelled');
    },

    /** @returns {string} 'idle' | 'playing' | 'done' */
    getState: () => state,

    /** @returns {number} 0..1 coarse timeline progress for the view */
    getProgress() {
      if (state === 'done') return 1;
      if (compiled.totalSec <= 0) return state === 'playing' ? 1 : 0;
      return Math.min(1, doneSec(root) / compiled.totalSec);
    },

    /** @returns {number} 0..1 hold-to-skip fill for the view's ring */
    getHoldProgress: () => holdProgress,

    /** @returns {boolean} true while a tapWait is active (show the hint) */
    isAwaitingTap() {
      if (state !== 'playing') return false;
      return someActive(root, (node) => node.step.op === 'tapWait');
    },

    /** @returns {boolean} */
    isReplay: () => replay,

    /** @returns {string|null} */
    getFinishReason: () => finishReason,

    /**
     * @param {(reason: string) => void} cb fired once on finish (any path)
     * @returns {() => void} unsubscribe
     */
    onFinish(cb) {
      finishCbs.push(cb);
      return () => {
        const i = finishCbs.indexOf(cb);
        if (i >= 0) finishCbs.splice(i, 1);
      };
    },
  };
}

// ---------------------------------------------------------------------------
// Seen-map save slice (additive — V5 vacation.js defaultSlice pattern)
// ---------------------------------------------------------------------------

/**
 * The cutscenes save slice at its defaults (defensive factory — consumers
 * self-heal a missing slice through this; NO SAVE.VERSION bump).
 * @returns {{seen: Record<string, boolean>}}
 */
export function defaultSlice() {
  return { seen: {} };
}

/**
 * Read the cutscenes slice off a save state, normalized + BOUNDED: only
 * known CUTSCENE_IDS survive (junk/removed ids are dropped), values coerce
 * to `true` only. Never mutates `state`.
 * @param {object} state save state (or any {cutscenes?} shape)
 * @returns {ReturnType<typeof defaultSlice>}
 */
export function sliceOf(state) {
  const raw = state?.cutscenes;
  const d = defaultSlice();
  if (raw == null || typeof raw !== 'object') return d;
  const seen = raw.seen;
  if (seen == null || typeof seen !== 'object' || Array.isArray(seen)) return d;
  for (const id of CUTSCENE_IDS) {
    if (seen[id] === true) d.seen[id] = true;
  }
  return d;
}

/**
 * A fresh slice with `id` marked seen (known ids only — unknown ids return
 * the normalized slice unchanged).
 * @param {object|null|undefined} prev previous cutscenes slice (or junk)
 * @param {string} id cutscene id
 * @returns {ReturnType<typeof defaultSlice>}
 */
export function markSeenSlice(prev, id) {
  const next = sliceOf({ cutscenes: prev });
  if (CUTSCENE_IDS.includes(id)) next.seen[id] = true;
  return next;
}

/**
 * Has this save watched cutscene `id` before? (Replay ⇒ instant tap-skip.)
 * @param {object} state save state
 * @param {string} id cutscene id
 * @returns {boolean}
 */
export function hasSeen(state, id) {
  return sliceOf(state).seen[id] === true;
}
