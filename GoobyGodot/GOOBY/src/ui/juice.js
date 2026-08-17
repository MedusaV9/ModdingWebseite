// V4/AC-9: interaction JUICE — the feedback layer that makes every tap feel
// like a real game instead of a demo. Four effects, all opt-out under
// prefers-reduced-motion and all pooled/cheap (SwiftShader VM + phones):
//   1. Universal press squash — ONE delegated pointerdown/up/cancel listener
//      set on the #ui root toggles `.ac-pressed` on any button/.btn/
//      [role="button"] (HUD buttons, tabs, nav dots included). The squash
//      uses the independent CSS `scale` property so it COMPOSES with base
//      transforms (rn-arrow's translateY centering, .btn:active) instead of
//      clobbering them.
//   2. Tap pop — a pooled one-shot radial burst of tiny leaves/stars/sparks
//      at the pointer on click (~320 ms, ≤4 concurrent, pooled DOM nodes).
//   3. Coin fly — flyCoins(fromEl|{x,y}, n) arcs 3–6 pooled coin sprites to
//      the HUD coin chip (.g5-coins) and bounces the chip on arrival.
//      Exposed as window.__goobyJuice AND as an ESM export so later packages
//      can wire call sites with a feature-detected one-liner.
//   4. Springy toasts — CSS-only: ui.js tags toasts `.juice-toast`; the
//      injected block below overrides the AC-1 enter/exit animations (the
//      toast queue/hold/flush logic in ui.js is untouched).
//
// SOUND CONTRACT (V3/FIX-B §D3.5): this layer adds NO press/tap sounds —
// screens own their own audio.play call sites and a delegated sound would
// double-fire. Only flyCoins() plays the EXISTING 'coin.fly' id, once per
// flight (no module fires a sound for a juice coin flight today; callers can
// opt out via {sfx: false}).
//
// Z-ORDER (POLISH-F ladder): the fx layer sits at calc(--z-toast - 40) —
// above all content (screens 100 / panels 200 / onboarding 300), below
// toasts (500), debug (600), drag (900) and system overlays (9000+).
//
// CSS is injected as <style data-owner="juice"> from the JUICE_CSS template
// literal below — px-audit gates it (§B3: rem-only in the audited props).
//
// The pure math helpers (pool index, arc interpolation, particle vectors,
// concurrency gate) are exported for test/juice.test.js (node:test, no DOM);
// importing this module in node is safe (no top-level DOM access).

import { prefersReducedMotion } from './ui.js';

// ---------------------------------------------------------------------------
// Pure helpers (exported for test/juice.test.js — keep them DOM-free)
// ---------------------------------------------------------------------------

/**
 * Round-robin pool index: wraps any (also negative) counter into [0, size).
 * @param {number} counter monotonically increasing use counter
 * @param {number} size pool size (>= 1)
 * @returns {number}
 */
export function poolIndex(counter, size) {
  const s = Math.max(1, Math.floor(size));
  const c = Math.floor(Number(counter) || 0);
  return ((c % s) + s) % s;
}

/**
 * First free slot in a busy-flag array (pop groups pick the first idle group
 * instead of blind round-robin so a long-running pop is never cut short).
 * @param {boolean[]} busy
 * @returns {number} index of the first `false` entry, or -1 when all busy
 */
export function nextFreeIndex(busy) {
  for (let i = 0; i < busy.length; i += 1) {
    if (!busy[i]) return i;
  }
  return -1;
}

/** Coin flights ship 3–6 sprites (§AC-9 contract). NaN/undefined → 4. */
export function clampCoinCount(n) {
  const v = Math.round(Number(n));
  if (!Number.isFinite(v)) return 4;
  return Math.min(6, Math.max(3, v));
}

/**
 * Arc height for a coin flight: proportional to the travel distance,
 * clamped so short hops still lift and cross-screen flights don't leave.
 * @param {{x: number, y: number}} from
 * @param {{x: number, y: number}} to
 * @returns {number} lift in px above the higher endpoint
 */
export function arcLift(from, to) {
  const dist = Math.hypot(to.x - from.x, to.y - from.y);
  return Math.min(180, Math.max(50, dist * 0.35));
}

/**
 * Quadratic-bezier arc interpolation: control point sits `lift` px above the
 * higher of the two endpoints, over the horizontal midpoint.
 * @param {{x: number, y: number}} from
 * @param {{x: number, y: number}} to
 * @param {number} lift
 * @param {number} t 0..1
 * @returns {{x: number, y: number}}
 */
export function arcPoint(from, to, lift, t) {
  const cx = (from.x + to.x) / 2;
  const cy = Math.min(from.y, to.y) - lift;
  const u = 1 - t;
  return {
    x: u * u * from.x + 2 * u * t * cx + t * t * to.x,
    y: u * u * from.y + 2 * u * t * cy + t * t * to.y,
  };
}

/**
 * WAAPI keyframes for one coin: translate along the arc, grow mid-air and
 * shrink into the chip. Transforms are relative to the start point (the coin
 * node is positioned at `from` via left/top).
 * @param {{x: number, y: number}} from
 * @param {{x: number, y: number}} to
 * @param {number} lift
 * @param {number} [steps]
 * @returns {Array<{offset: number, transform: string, opacity: number}>}
 */
export function arcKeyframes(from, to, lift, steps = 8) {
  const frames = [];
  const n = Math.max(2, Math.floor(steps));
  for (let i = 0; i <= n; i += 1) {
    const t = i / n;
    const p = arcPoint(from, to, lift, t);
    const scale = 1 + 0.3 * Math.sin(Math.PI * t) - 0.45 * t;
    frames.push({
      offset: t,
      transform: `translate(${(p.x - from.x).toFixed(1)}px, ${(p.y - from.y).toFixed(1)}px) scale(${scale.toFixed(3)})`,
      opacity: 1,
    });
  }
  return frames;
}

/**
 * Radial burst vectors for one tap pop: evenly spread angles with jitter, a
 * slight upward bias (reads as a happy "poof", not an explosion). Injectable
 * rand keeps the math deterministic for tests.
 * @param {number} count
 * @param {number} radius spread radius in px
 * @param {() => number} [rand]
 * @returns {Array<{dx: number, dy: number, rot: number, scale: number}>}
 */
export function popVectors(count, radius, rand = Math.random) {
  const out = [];
  for (let i = 0; i < count; i += 1) {
    const angle = (i / count) * Math.PI * 2 + (rand() - 0.5) * 0.9;
    const dist = radius * (0.65 + rand() * 0.55);
    out.push({
      dx: Math.cos(angle) * dist,
      dy: Math.sin(angle) * dist - radius * 0.2,
      rot: (rand() - 0.5) * 260,
      scale: 0.7 + rand() * 0.6,
    });
  }
  return out;
}

/**
 * Concurrency + reduced-motion gate for one effect family. tryAcquire()
 * returns false (effect skipped) when the OS asks for reduced motion or the
 * concurrent cap is reached; release() never underflows.
 * @param {{cap?: number, reducedMotion?: () => boolean}} [opts]
 */
export function createEffectGate({ cap = 4, reducedMotion = () => false } = {}) {
  let active = 0;
  return {
    tryAcquire() {
      if (reducedMotion() || active >= cap) return false;
      active += 1;
      return true;
    },
    release() {
      active = Math.max(0, active - 1);
    },
    active: () => active,
  };
}

// ---------------------------------------------------------------------------
// Tuning constants
// ---------------------------------------------------------------------------

const POP_POOL = 4; // max concurrent pops (== pool size)
const POP_PARTS = 6; // particles per pop group
const POP_MS = 340;
const POP_RADIUS = 44; // px spread
const COIN_POOL = 6;
const COIN_MS = 620;
const COIN_STAGGER_MS = 70;
const PRESS_SELECTOR = 'button, .btn, [role="button"]';
const RELEASE_CLEAR_MS = 260; // fallback when animationend never fires

// px-audit gates this literal (§B3): rem-only in font-size/padding/margin/
// gap/border-radius/letter-spacing. left/top/transform px values are exempt
// by design (positioning, not typography/spacing).
const JUICE_CSS = `
/* V4/AC-9 injected juice CSS — see src/ui/juice.js header for the contract */
.juice-layer{position:fixed;inset:0;pointer-events:none;z-index:calc(var(--z-toast) - 40);}

/* universal press squash: independent scale property composes with any base
   transform (rn-arrow translateY centering, .btn:active) instead of
   overriding it */
.ac-pressed{scale:.94;animation:juice-press-in var(--dur-pop) var(--ease-spring);}
.ac-release{animation:juice-press-out calc(var(--dur-pop) * 1.4) var(--ease-spring);}
@keyframes juice-press-in{from{scale:1;}to{scale:.94;}}
@keyframes juice-press-out{from{scale:.94;}to{scale:1;}}

/* tap-pop particles (pooled nodes; WAAPI drives per-burst motion) */
.juice-pop{position:absolute;}
.juice-p{position:absolute;display:block;opacity:0;will-change:transform,opacity;}
.juice-p-leaf{width:0.75rem;height:0.75rem;background:linear-gradient(135deg,var(--leaf),var(--leaf-dark));border-radius:999px 0.1875rem;box-shadow:0 0 0.25rem rgba(143,208,108,0.5);}
.juice-p-star{width:0.6875rem;height:0.6875rem;background:var(--gold);clip-path:polygon(50% 0%,63% 38%,100% 50%,63% 62%,50% 100%,37% 62%,0% 50%,37% 38%);}
.juice-p-spark{width:0.5rem;height:0.5rem;border-radius:999px;background:#fff;box-shadow:0 0 0.5rem rgba(255,211,77,0.95);}

/* coin sprites: carrot-coin art over a gold-gradient fallback */
.juice-coin{position:absolute;width:1.375rem;height:1.375rem;margin:-0.6875rem 0 0 -0.6875rem;border-radius:999px;background:var(--acui-coin) center / contain no-repeat,radial-gradient(circle at 35% 30%,#ffe9a8,#ffd166 55%,#e0a93e);box-shadow:0 0.0625rem 0.25rem rgba(74,59,54,0.35);opacity:0;will-change:transform,opacity;}

/* springy toasts: override AC-1's toast-in/out pair for .juice-toast tags
   (ui.js queue/hold/flush contract untouched — exit settles at 220 ms, well
   inside ui.js' 300 ms removal window) */
.toast.juice-toast{animation:juice-toast-in 420ms cubic-bezier(0.22,0.9,0.35,1) backwards;}
@keyframes juice-toast-in{
  0%{transform:translate(-50%,150%) scale(0.82);opacity:0;}
  55%{transform:translate(-50%,-9%) scale(1.05);opacity:1;}
  74%{transform:translate(-50%,3.5%) scale(0.976) rotate(-0.8deg);}
  88%{transform:translate(-50%,-1.5%) scale(1.012) rotate(0.5deg);}
  100%{transform:translate(-50%,0) scale(1);opacity:1;}
}
.toast.juice-toast.toast-out{animation:juice-toast-out 220ms cubic-bezier(0.55,0,0.8,0.4) forwards;}
@keyframes juice-toast-out{
  0%{transform:translate(-50%,0) scale(1);opacity:1;}
  30%{transform:translate(-50%,-6%) scale(1.03);opacity:1;}
  100%{transform:translate(-50%,90%) scale(0.8);opacity:0;}
}
/* action toasts get a nudging chevron affordance (::before is the leaf) */
.toast.juice-toast.toast-action::after{content:'\\203A';display:inline-block;margin-left:0.5rem;font-weight:800;opacity:0.65;animation:juice-chevron 1.2s ease-in-out infinite;}
@keyframes juice-chevron{0%,100%{transform:translateX(0);}50%{transform:translateX(0.1875rem);}}

/* reduced motion: collapse everything (the JS side also skips spawning) */
@media (prefers-reduced-motion: reduce){
  .ac-pressed,.ac-release{scale:none;animation:none;}
  .toast.juice-toast{animation-duration:1ms;}
  .toast.juice-toast.toast-out{animation-duration:1ms;}
  .toast.juice-toast.toast-action::after{animation:none;}
  .juice-pop,.juice-coin{display:none;}
}
`;

// ---------------------------------------------------------------------------
// DOM wiring (single init from main.js' marked V4/AC-9 block)
// ---------------------------------------------------------------------------

/** @type {null | {
 *   root: HTMLElement, layer: HTMLElement, audio: object|null,
 *   pops: Array<{el: HTMLElement, parts: HTMLElement[]}>, popBusy: boolean[],
 *   coins: HTMLElement[], coinCounter: number,
 *   pressed: Map<number, HTMLElement>,
 *   stats: {pops: number, coinFlights: number},
 *   gate: ReturnType<typeof createEffectGate>, api: object|null,
 * }} */
let state = null;

/** Nearest juice-able press target for a delegated event, or null. */
function pressTargetFrom(target) {
  if (!target || typeof target.closest !== 'function') return null;
  const el = target.closest(PRESS_SELECTOR);
  return el && el.disabled !== true ? el : null;
}

function onPressDown(e) {
  if (!state || prefersReducedMotion()) return;
  const el = pressTargetFrom(e.target);
  if (!el) return;
  el.classList.remove('ac-release');
  el.classList.add('ac-pressed');
  state.pressed.set(e.pointerId ?? -1, el);
}

function onPressUp(e) {
  if (!state) return;
  const el = state.pressed.get(e.pointerId ?? -1);
  if (!el) return;
  state.pressed.delete(e.pointerId ?? -1);
  if (!el.classList.contains('ac-pressed')) return;
  el.classList.remove('ac-pressed');
  el.classList.add('ac-release');
  const clear = () => el.classList.remove('ac-release');
  el.addEventListener('animationend', clear, { once: true });
  setTimeout(clear, RELEASE_CLEAR_MS); // hidden tab / interrupted animation
}

function onTapPop(e) {
  if (!state || prefersReducedMotion()) return;
  const el = pressTargetFrom(e.target);
  if (!el) return;
  let x = e.clientX;
  let y = e.clientY;
  if (!e.detail || (x === 0 && y === 0)) {
    // keyboard/synthetic activation: burst from the control's center
    const r = el.getBoundingClientRect();
    x = r.left + r.width / 2;
    y = r.top + r.height / 2;
  }
  spawnPop(x, y);
}

/** Lazily build the pooled pop groups (POP_POOL × POP_PARTS nodes, once). */
function ensurePopGroups() {
  while (state.pops.length < POP_POOL) {
    const g = document.createElement('div');
    g.className = 'juice-pop';
    const kinds = ['leaf', 'star', 'spark', 'leaf', 'spark', 'star'];
    const parts = [];
    for (let i = 0; i < POP_PARTS; i += 1) {
      const p = document.createElement('span');
      p.className = `juice-p juice-p-${kinds[i % kinds.length]}`;
      g.appendChild(p);
      parts.push(p);
    }
    state.layer.appendChild(g);
    state.pops.push({ el: g, parts });
    state.popBusy.push(false);
  }
}

/** One pooled radial pop at client coords (skipped when the gate is closed). */
function spawnPop(x, y) {
  if (!state.gate.tryAcquire()) return;
  ensurePopGroups();
  const idx = nextFreeIndex(state.popBusy);
  if (idx < 0) {
    state.gate.release();
    return;
  }
  state.popBusy[idx] = true;
  state.stats.pops += 1;
  const group = state.pops[idx];
  group.el.style.left = `${x}px`;
  group.el.style.top = `${y}px`;
  const vecs = popVectors(group.parts.length, POP_RADIUS);
  const anims = [];
  group.parts.forEach((p, i) => {
    p.getAnimations?.().forEach((a) => a.cancel());
    const v = vecs[i];
    const anim = p.animate?.(
      [
        { transform: 'translate(0, 0) scale(0.5) rotate(0deg)', opacity: 1 },
        // hold full opacity through the fling, fade only on the last third
        { transform: `translate(${(v.dx * 0.72).toFixed(1)}px, ${(v.dy * 0.72).toFixed(1)}px) scale(${v.scale.toFixed(2)}) rotate(${(v.rot * 0.7).toFixed(0)}deg)`, opacity: 1, offset: 0.62 },
        { transform: `translate(${v.dx.toFixed(1)}px, ${v.dy.toFixed(1)}px) scale(${(v.scale * 0.8).toFixed(2)}) rotate(${v.rot.toFixed(0)}deg)`, opacity: 0 },
      ],
      { duration: POP_MS, easing: 'cubic-bezier(0.16, 0.84, 0.44, 1)', fill: 'forwards' }
    );
    if (anim) anims.push(anim);
  });
  // Free the group when the burst really finishes (correct even when the
  // document timeline is slowed/throttled); the generous fallback timer
  // guarantees the pool can't jam closed in hidden tabs where finish
  // promises starve.
  let freed = false;
  const free = () => {
    if (freed) return;
    freed = true;
    group.parts.forEach((p) => p.getAnimations?.().forEach((a) => a.cancel()));
    state.popBusy[idx] = false;
    state.gate.release();
  };
  Promise.allSettled(anims.map((a) => a.finished)).then(free);
  setTimeout(free, POP_MS * 3);
}

/** Center of an element's rect (null for detached/zero-size elements). */
function centerOf(el) {
  const r = el?.getBoundingClientRect?.();
  return r && (r.width > 0 || r.height > 0)
    ? { x: r.left + r.width / 2, y: r.top + r.height / 2 }
    : null;
}

/** Lazily build the pooled coin sprites (COIN_POOL nodes, once). */
function ensureCoins() {
  while (state.coins.length < COIN_POOL) {
    const c = document.createElement('div');
    c.className = 'juice-coin';
    state.layer.appendChild(c);
    state.coins.push(c);
  }
}

/**
 * V4/AC-9 API: arc 3–6 pooled coin sprites from `from` to the HUD coin chip
 * (.g5-coins), bounce the chip and play the existing 'coin.fly' cue once.
 * Feature-detected call-site one-liner for later packages:
 *   window.__goobyJuice?.flyCoins(sourceEl, 5);
 * @param {HTMLElement|{x: number, y: number}|null|undefined} from source
 *   element or client coords (defaults to the viewport center)
 * @param {number} [n] requested coins (clamped 3–6; NaN → 4)
 * @param {{sfx?: boolean}} [opts] pass {sfx: false} to keep the flight silent
 *   (e.g. when the caller's own coin sfx already fires on the same beat)
 * @returns {number} coins spawned (0 when uninitialized or reduced motion)
 */
export function flyCoins(from, n, opts = {}) {
  if (!state || prefersReducedMotion()) return 0;
  const src = centerOf(from)
    ?? (Number.isFinite(from?.x) && Number.isFinite(from?.y) ? { x: from.x, y: from.y } : null)
    ?? { x: innerWidth / 2, y: innerHeight / 2 };
  const chip = document.querySelector('.g5-coins');
  const to = centerOf(chip) ?? { x: 72, y: 90 }; // HUD chip's usual corner
  const count = clampCoinCount(n);
  ensureCoins();
  state.stats.coinFlights += 1;
  const flightId = String(state.stats.coinFlights);
  const used = [];
  for (let i = 0; i < count; i += 1) {
    const coin = state.coins[poolIndex(state.coinCounter, COIN_POOL)];
    state.coinCounter += 1;
    coin.getAnimations?.().forEach((a) => a.cancel()); // steal from older flights
    coin.dataset.flight = flightId;
    const start = {
      x: src.x + (Math.random() - 0.5) * 26,
      y: src.y + (Math.random() - 0.5) * 18,
    };
    coin.style.left = `${start.x}px`;
    coin.style.top = `${start.y}px`;
    const lift = arcLift(start, to) * (0.8 + Math.random() * 0.5);
    // No fill:forwards — after the arc the coin reverts to its base opacity:0
    // (fill:backwards shows the staggered coins piled on the source instead).
    coin.animate?.(arcKeyframes(start, to, lift), {
      duration: COIN_MS + Math.random() * 90,
      delay: i * COIN_STAGGER_MS,
      easing: 'linear',
      fill: 'backwards',
    });
    used.push(coin);
  }
  const settleMs = COIN_MS + 90 + (count - 1) * COIN_STAGGER_MS;
  setTimeout(() => {
    for (const c of used) {
      if (c.dataset.flight === flightId) c.getAnimations?.().forEach((a) => a.cancel());
    }
    // Chip bounce on arrival (the chip has no base transform — safe to WAAPI).
    chip?.animate?.(
      [
        { transform: 'scale(1)' },
        { transform: 'scale(1.16)', offset: 0.35 },
        { transform: 'scale(0.94)', offset: 0.7 },
        { transform: 'scale(1)' },
      ],
      { duration: 300, easing: 'ease-out' }
    );
    if (opts.sfx !== false) state.audio?.play?.('coin.fly'); // EXISTING id (§D3.5)
  }, settleMs);
  return count;
}

/**
 * Wire the juice layer once (called from main.js' marked V4/AC-9 block).
 * Safe to call in any order relative to screens/HUD — everything is
 * delegated/lazy. No-ops (returns null) without a DOM or #ui root.
 * @param {{ui?: {el?: HTMLElement}, audio?: object}} [deps]
 * @returns {object|null} the { flyCoins, getStats } api (also on
 *   window.__goobyJuice)
 */
export function initJuice({ ui, audio } = {}) {
  if (state) return state.api;
  if (typeof document === 'undefined') return null;
  const root = ui?.el ?? document.getElementById('ui');
  if (!root) return null;

  if (!document.querySelector('style[data-owner="juice"]')) {
    const style = document.createElement('style');
    style.dataset.owner = 'juice';
    style.textContent = JUICE_CSS;
    document.head.appendChild(style);
  }

  const layer = document.createElement('div');
  layer.className = 'juice-layer';
  root.appendChild(layer);

  state = {
    root,
    layer,
    audio: audio ?? null,
    pops: [],
    popBusy: [],
    coins: [],
    coinCounter: 0,
    pressed: new Map(),
    stats: { pops: 0, coinFlights: 0 },
    gate: createEffectGate({ cap: POP_POOL, reducedMotion: prefersReducedMotion }),
    api: null,
  };

  // Capture phase: the root is outermost, so no child stopPropagation can
  // hide a press from the juice layer; passive — we never preventDefault.
  root.addEventListener('pointerdown', onPressDown, { capture: true, passive: true });
  window.addEventListener('pointerup', onPressUp, { capture: true, passive: true });
  window.addEventListener('pointercancel', onPressUp, { capture: true, passive: true });
  root.addEventListener('click', onTapPop, { capture: true, passive: true });

  const api = {
    flyCoins,
    getStats: () => ({ ...state.stats, activePops: state.gate.active() }),
  };
  state.api = api;
  window.__goobyJuice = api; // feature-detected handle for later call-site wiring
  return api;
}
