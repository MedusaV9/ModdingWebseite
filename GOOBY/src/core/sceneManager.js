// Scene manager (§E1): owns the WebGLRenderer, the single canvas, resize
// handling and the RAF loop. register(id, factory) / switchTo(id, params).
// Lifecycle: factory(ctx) → { scene, camera, enter(params), update(dt), exit(),
// dispose() }. Switches fade through a 150 ms black overlay, dispose old scene
// resources, preload the new scene's asset keys, then enter.

import * as THREE from 'three';
import { ENGINE } from '../data/constants.js';

// ── V4/PERF: retina-aware pixel-ratio cap (§E0.1-2 module-local tuning) ─────
// `ENGINE.MAX_PIXEL_RATIO` (2, frozen constants.js) stays the SAFE baseline:
// it is what software rasterizers (SwiftShader/llvmpipe VMs) keep. Only an
// EXPLICITLY recognized hardware GPU raises the cap to 3 so DPR-3 phones
// (iPhone Pro class) render at native resolution instead of a blurry
// 2/3-width upscale; unknown/ambiguous renderer strings keep the baseline
// (V4/FIX-SM defect 4 — fail CLOSED, never open). Only devices whose DPR
// actually exceeds 2 are affected — desktop DPR-1/2 output is unchanged.
export const RENDER_SCALE = Object.freeze({
  /** Pixel-ratio cap on explicitly recognized hardware WebGL — full retina sharpness. */
  MAX_PIXEL_RATIO_HW: 3,
});

/**
 * Whether a WebGL renderer string names a software rasterizer (SwiftShader,
 * llvmpipe, softpipe, Microsoft Basic Render, "software renderer" ANGLE
 * spellings). Pure — same detection family as goobyWelt's splat guard, kept
 * module-local because core/ must not import game modules. Unknown/empty
 * strings return false (not software) — classifyGlRenderer maps those to
 * 'unknown', which keeps the conservative baseline cap (V4/FIX-SM).
 * @param {string|null|undefined} rendererString GL renderer string
 * @returns {boolean}
 */
export function isSoftwareGl(rendererString) {
  if (typeof rendererString !== 'string' || rendererString === '') return false;
  return /swiftshader|llvmpipe|softpipe|software\s*(rasterizer|renderer|adapter)|microsoft basic render/i
    .test(rendererString);
}

/**
 * V4/FIX-SM (defect 4): three-way GL classification for the pixel-ratio cap.
 * 'software' → known software rasterizer; 'hardware' → a KNOWN hardware GPU
 * family (Apple / Adreno / Mali / Immortalis / Xclipse / PowerVR / NVIDIA /
 * GeForce / RTX / GTX / Quadro / AMD / Radeon / Intel / Iris); 'unknown' →
 * empty or unrecognized strings. Unknown is deliberately CONSERVATIVE: it
 * keeps the frozen `ENGINE.MAX_PIXEL_RATIO` baseline of 2 instead of failing
 * open to the DPR-3 hardware cap (2.25× the pixels). Pure — unit-tested.
 * @param {string|null|undefined} rendererString GL renderer string
 * @returns {'software'|'hardware'|'unknown'}
 */
export function classifyGlRenderer(rendererString) {
  if (isSoftwareGl(rendererString)) return 'software';
  if (typeof rendererString !== 'string' || rendererString.trim() === '') return 'unknown';
  return /\bapple\b|adreno|\bmali\b|immortalis|xclipse|powervr|nvidia|geforce|\brtx\b|\bgtx\b|quadro|\bamd\b|radeon|\bintel\b|\biris\b/i
    .test(rendererString)
    ? 'hardware'
    : 'unknown';
}

/**
 * Effective renderer pixel ratio (pure decision, unit-tested): only an
 * EXPLICIT 'hardware' classification raises the cap to
 * `RENDER_SCALE.MAX_PIXEL_RATIO_HW`; 'software', 'unknown' and any garbage
 * classification keep the frozen `ENGINE.MAX_PIXEL_RATIO` baseline — the
 * decision fails CLOSED (V4/FIX-SM defect 4). Non-finite/non-positive DPR
 * inputs fall back to 1.
 * @param {number} dpr window.devicePixelRatio (may be undefined/garbage)
 * @param {'software'|'hardware'|'unknown'} glClass from classifyGlRenderer()
 * @returns {number}
 */
export function computePixelRatio(dpr, glClass) {
  const d = Number.isFinite(dpr) && dpr > 0 ? dpr : 1;
  const cap = glClass === 'hardware' ? RENDER_SCALE.MAX_PIXEL_RATIO_HW : ENGINE.MAX_PIXEL_RATIO;
  return Math.min(d, cap);
}

/**
 * Read the unmasked GL renderer string off a live WebGLRenderer ('' when the
 * probe is unavailable — classifyGlRenderer maps that to 'unknown', which
 * keeps the conservative baseline cap).
 * @param {import('three').WebGLRenderer} renderer
 * @returns {string}
 */
function glRendererString(renderer) {
  try {
    const gl = renderer?.getContext?.();
    if (!gl) return '';
    const info = gl.getExtension('WEBGL_debug_renderer_info');
    return String(gl.getParameter(info ? info.UNMASKED_RENDERER_WEBGL : gl.RENDERER) ?? '');
  } catch {
    return '';
  }
}
// ── end V4/PERF ──────────────────────────────────────────────────────────────

// ── V4/FIX-SM: crash-proof frame loop + failed-switch teardown (pure) ────────

/** Frame-time clamp (s) — one hitched frame never advances a scene > 100 ms. */
const MAX_FRAME_DT_SEC = 0.1;

/**
 * Build the RAF frame callback (pure factory, unit-tested). Crash-proof
 * ordering (V4/FIX-SM defect 1): the NEXT frame is scheduled FIRST, and
 * update() and render() are try/caught INDEPENDENTLY, so a throwing scene —
 * or a renderer throw during e.g. GPU context loss — can never kill the loop.
 * Before this, `renderer.render` ran unguarded and the reschedule came last:
 * one render throw froze the whole game permanently.
 * @param {{
 *   schedule: (cb: (t: number) => void) => void,
 *   getInstance: () => ({update?: (dt: number) => void, scene?: object, camera?: object}|null|undefined),
 *   render: (scene: object, camera: object) => void,
 *   initialT?: number,
 * }} deps schedule = requestAnimationFrame in production
 * @returns {(t: number) => void} the frame callback to schedule once
 */
export function createFrameRunner({ schedule, getInstance, render, initialT = 0 }) {
  let lastT = initialT;
  return function frame(t) {
    // Reschedule BEFORE any scene work — the loop survives anything below.
    schedule(frame);
    const dt = Math.min((t - lastT) / 1000, MAX_FRAME_DT_SEC);
    lastT = t;
    const inst = getInstance();
    if (!inst) return;
    try {
      inst.update?.(dt);
    } catch (err) {
      console.error('[sceneManager] scene update error:', err);
    }
    try {
      if (inst.scene && inst.camera) render(inst.scene, inst.camera);
    } catch (err) {
      console.error('[sceneManager] scene render error:', err);
    }
  };
}

/**
 * Best-effort teardown of a partially-built scene instance after a failed
 * switchTo (V4/FIX-SM defect 2). Every step is guarded independently and the
 * function NEVER throws — the caller must still be able to lift the black
 * fade overlay afterwards. A Promise-returning dispose (V4/G56 async splat
 * release) is awaited so GPU resources are actually gone.
 * @param {SceneLifecycle|null|undefined} instance possibly-partial instance
 * @param {{removeAll: () => void}|null|undefined} scopedInput its input scope
 * @returns {Promise<void>}
 */
export async function disposeFailedSwitch(instance, scopedInput) {
  try {
    instance?.exit?.();
  } catch (err) {
    console.error('[sceneManager] failed-switch exit error:', err);
  }
  try {
    await instance?.dispose?.();
  } catch (err) {
    console.error('[sceneManager] failed-switch dispose error:', err);
  }
  try {
    scopedInput?.removeAll?.();
  } catch (err) {
    console.error('[sceneManager] failed-switch input release error:', err);
  }
}
// ── end V4/FIX-SM ────────────────────────────────────────────────────────────

/**
 * @typedef {Object} SceneLifecycle
 * @property {import('three').Scene} scene
 * @property {import('three').Camera} camera
 * @property {(params?: object) => (void|Promise<void>)} [enter]
 * @property {(dt: number) => void} [update] dt in real seconds (clamped)
 * @property {() => void} [exit]
 * @property {() => (void|Promise<void>)} [dispose] must free geometries/
 *   materials it created. V4/G56 (§G6.6): MAY return a Promise (goobyWelt's
 *   splat release) — switchTo awaits it before building the next scene.
 */

/**
 * @param {{canvas: HTMLCanvasElement, assets: object, input: object, audio: object, store: object, ui: object}} deps
 */
export function createSceneManager({ canvas, assets, input, audio, store, ui }) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  // V4/PERF + V4/FIX-SM defect 4: retina-aware cap — only an explicitly
  // recognized hardware GPU goes to 3 (native DPR-3 phones); software GL
  // (SwiftShader/llvmpipe) AND unknown/ambiguous renderer strings keep the
  // ENGINE.MAX_PIXEL_RATIO baseline of 2 (conservative default), i.e. exactly
  // the pre-V4 behavior on the headless VM and on unidentifiable GPUs.
  const glClass = classifyGlRenderer(glRendererString(renderer));
  renderer.setPixelRatio(computePixelRatio(devicePixelRatio, glClass));
  renderer.setSize(innerWidth, innerHeight);

  /** @type {Map<string, {factory: (ctx: object) => SceneLifecycle, assetKeys: string[]}>} */
  const registry = new Map();
  /** @type {{id: string, instance: SceneLifecycle, scopedInput: {removeAll: () => void}}|null} */
  let current = null;
  let switching = false;
  /** V4/AC-3: one-shot listeners fired right after the next enter() resolves. */
  const afterEnterCbs = [];

  // --- fade overlay (150 ms, §E1). Stepped with timers (not CSS transitions /
  // RAF) so headless virtual-time screenshots and throttled tabs always see a
  // completed fade — timer chains are fast-forwarded deterministically. ---
  const fadeEl = document.createElement('div');
  fadeEl.style.cssText = 'position:fixed;inset:0;background:#000;pointer-events:none;opacity:0;z-index:9999;';
  document.body.appendChild(fadeEl);
  let fadeToken = 0;

  /** @param {number} target opacity 0|1 */
  function fadeTo(target) {
    const token = ++fadeToken;
    const stepMs = 16;
    const steps = Math.max(1, Math.round(ENGINE.SCENE_FADE_MS / stepMs));
    const from = parseFloat(fadeEl.style.opacity) || 0;
    return new Promise((resolve) => {
      let i = 0;
      const step = () => {
        if (token !== fadeToken) return resolve(); // superseded by a newer fade
        i += 1;
        fadeEl.style.opacity = String(from + ((target - from) * i) / steps);
        if (i >= steps) resolve();
        else setTimeout(step, stepMs);
      };
      setTimeout(step, stepMs);
    });
  }

  // --- resize ---
  function onResize() {
    // V4/FIX-SM defect 4 hardening: DPR can change at runtime (browser zoom,
    // window moved across displays) — recompute the capped pixel ratio from
    // the live devicePixelRatio on every resize. The GL class is fixed for
    // the context's lifetime, so it is classified once above.
    renderer.setPixelRatio(computePixelRatio(devicePixelRatio, glClass));
    renderer.setSize(innerWidth, innerHeight);
    const cam = current?.instance?.camera;
    if (cam && cam.isPerspectiveCamera) {
      cam.aspect = innerWidth / innerHeight;
      cam.updateProjectionMatrix();
    }
  }
  window.addEventListener('resize', onResize);

  // ── V4/FIX-SM defect 3: manager-level WebGL context-loss recovery ─────────
  // Only goobyWelt/splatViewer handled 'webglcontextlost' before — home and
  // every other game froze for good if iOS reclaimed the GPU. preventDefault
  // on 'lost' tells the browser the context is restorable; on 'restored',
  // three re-initializes its GL state internally, so the manager re-applies
  // pixel ratio + size and re-renders the current scene immediately instead
  // of waiting for the next RAF (which may be throttled in a background tab).
  function onContextLost(e) {
    e?.preventDefault?.();
    console.warn('[sceneManager] WebGL context lost — preventDefault, awaiting restore');
  }
  function onContextRestored() {
    console.warn('[sceneManager] WebGL context restored — refreshing renderer');
    try {
      renderer.setPixelRatio(computePixelRatio(devicePixelRatio, glClass));
      renderer.setSize(innerWidth, innerHeight);
      const inst = current?.instance;
      if (inst?.scene && inst?.camera) renderer.render(inst.scene, inst.camera);
    } catch (err) {
      console.error('[sceneManager] context-restore re-render failed:', err);
    }
  }
  canvas.addEventListener('webglcontextlost', onContextLost);
  canvas.addEventListener('webglcontextrestored', onContextRestored);
  // ── end V4/FIX-SM defect 3 ─────────────────────────────────────────────────

  // --- RAF loop (V4/FIX-SM defect 1: crash-proof — see createFrameRunner) ---
  const frame = createFrameRunner({
    schedule: (cb) => requestAnimationFrame(cb),
    getInstance: () => current?.instance,
    render: (scene, camera) => renderer.render(scene, camera),
    initialT: performance.now(),
  });
  requestAnimationFrame(frame);

  const manager = {
    renderer,

    /**
     * Register a scene factory.
     * @param {string} id scene id ('home', 'minigame', dev scenes…)
     * @param {(ctx: object) => SceneLifecycle} factory
     * @param {string[]} [assetKeys] preloaded via assets.preload before enter
     */
    register(id, factory, assetKeys = []) {
      registry.set(id, { factory, assetKeys });
    },

    /** @param {string} id @returns {boolean} */
    has(id) {
      return registry.has(id);
    },

    /** @returns {string|null} active scene id */
    currentId() {
      return current?.id ?? null;
    },

    /**
     * F6 (RE5): read-only "a switchTo is in flight" flag. During the fade the
     * OLD scene can still be current (fade-out phase), so currentId() alone
     * cannot tell callers whether a queued switch will still change scenes —
     * the minigame framework's launch retry needs this to avoid a false
     * "already there" while a switch AWAY is mid-flight.
     * @returns {boolean}
     */
    isSwitching() {
      return switching;
    },

    /**
     * V4/AC-3 (additive): register a ONE-SHOT callback fired right after the
     * NEXT scene enter() resolves (before the fade lifts). The loading veil
     * (ui/loadingVeil.js) times its anti-pop-in reveal off this.
     * @param {(id: string) => void} cb
     */
    afterEnter(cb) {
      afterEnterCbs.push(cb);
    },

    // ── V2/G23: photo-mode capture (§C12.2) ─────────────────────────────────
    /**
     * Render the current scene once and read the canvas back as a PNG blob.
     * The render + toBlob happen in the SAME task, so the WebGL backbuffer is
     * still valid — no preserveDrawingBuffer needed (§C12.2 capture pipeline).
     * @returns {Promise<Blob|null>} null when no scene is active or toBlob fails
     */
    captureFrame() {
      const inst = current?.instance;
      if (!inst?.scene || !inst?.camera) return Promise.resolve(null);
      try {
        renderer.render(inst.scene, inst.camera);
      } catch (err) {
        console.error('[sceneManager] captureFrame render failed:', err);
        return Promise.resolve(null);
      }
      return new Promise((resolve) => {
        try {
          renderer.domElement.toBlob((blob) => resolve(blob), 'image/png');
        } catch (err) {
          console.error('[sceneManager] captureFrame toBlob failed:', err);
          resolve(null);
        }
      });
    },
    // ── end V2/G23 ──────────────────────────────────────────────────────────

    /**
     * Switch to a scene (§E1): fade out → exit+dispose old → preload assets →
     * enter new → fade in.
     * @param {string} id
     * @param {object} [params] passed to the scene's enter()
     * @returns {Promise<void>}
     */
    async switchTo(id, params = {}) {
      const entry = registry.get(id);
      if (!entry) throw new Error(`[sceneManager] unknown scene '${id}'`);
      if (switching) {
        console.warn(`[sceneManager] switchTo('${id}') ignored — switch in progress`);
        return;
      }
      switching = true;
      /** @type {SceneLifecycle|null} */
      let instance = null;
      /** @type {{removeAll: () => void}|null} */
      let scopedInput = null;
      try {
        await fadeTo(1);
        if (current) {
          try {
            current.instance.exit?.();
            // V4/G56 (§G6.6): a Promise-returning dispose (async splat
            // release) is AWAITED so the old scene's GPU resources are gone
            // before the next scene builds. Sync disposes return undefined —
            // awaiting that is a no-op (existing scenes unaffected).
            await current.instance.dispose?.();
          } catch (err) {
            console.error('[sceneManager] error disposing scene:', err);
          }
          // V4/PERF: safety sweep AFTER the scene's own dispose — frees
          // geometries/materials the departing scene missed (measured: +12
          // geometries per home↔minigame cycle before this). Mirrors the
          // minigame framework's V2/FIX-F P2-3 sweep exactly: permanent-cache
          // masters (assets.isCachedResource) and userData.shared resources
          // are SKIPPED, and re-disposing already-freed resources is a no-op,
          // so scenes that clean up fully are unaffected.
          try {
            const isShared = (res) =>
              assets?.isCachedResource?.(res) === true || res?.userData?.shared === true;
            current.instance.scene?.traverse?.((obj) => {
              if (obj.geometry && !isShared(obj.geometry)) obj.geometry.dispose?.();
              if (obj.material) {
                for (const m of Array.isArray(obj.material) ? obj.material : [obj.material]) {
                  if (!isShared(m)) m.dispose?.();
                }
              }
            });
          } catch (err) {
            console.error('[sceneManager] dispose sweep error:', err);
          }
          current.scopedInput.removeAll();
          current = null;
          // V4/PERF: promptly drop the old scene's render lists. They are
          // WeakMap-keyed (GC-safe either way), but releasing them here frees
          // the sorted draw arrays before the next scene builds instead of
          // waiting for a collection; the new scene's lists rebuild on its
          // first render. Shared cached assets are untouched — this releases
          // renderer-internal bookkeeping only, never geometry/materials.
          renderer.renderLists?.dispose?.();
        }
        scopedInput = input.scoped();
        const ctx = { renderer, assets, input: scopedInput, audio, store, ui };
        instance = entry.factory(ctx);
        current = { id, instance, scopedInput };
        if (instance.camera?.isPerspectiveCamera) {
          instance.camera.aspect = innerWidth / innerHeight;
          instance.camera.updateProjectionMatrix();
        }
        try {
          await assets?.preload?.(entry.assetKeys);
        } catch (err) {
          console.warn('[sceneManager] asset preload failed:', err);
        }
        await instance.enter?.(params);
        // V4/AC-3: flush the one-shot afterEnter listeners (loading veil)
        for (const cb of afterEnterCbs.splice(0)) {
          try {
            cb(id);
          } catch (err) {
            console.error('[sceneManager] afterEnter callback error:', err);
          }
        }
        await fadeTo(0);
      } catch (err) {
        // V4/FIX-SM defect 2: a throwing factory()/enter() used to strand the
        // 150 ms black fade at opacity 1 forever — the old scene was already
        // disposed and fadeTo(0) never ran, trapping the player behind a
        // permanent black overlay. Dispose whatever partial instance exists,
        // LIFT the fade, then rethrow so callers still see the failure. When
        // the throw happened before the old scene was torn down (current
        // still points at it), the old scene is left in place so it keeps
        // rendering after the fade lifts.
        console.error(`[sceneManager] switchTo('${id}') failed — recovering:`, err);
        if (current && current.instance === instance) current = null;
        await disposeFailedSwitch(instance, scopedInput);
        await fadeTo(0);
        throw err;
      } finally {
        switching = false;
      }
    },
  };

  return manager;
}
