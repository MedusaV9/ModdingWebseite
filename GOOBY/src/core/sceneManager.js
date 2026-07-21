// Scene manager (§E1): owns the WebGLRenderer, the single canvas, resize
// handling and the RAF loop. register(id, factory) / switchTo(id, params).
// Lifecycle: factory(ctx) → { scene, camera, enter(params), update(dt), exit(),
// dispose() }. Switches fade through a 150 ms black overlay, dispose old scene
// resources, preload the new scene's asset keys, then enter.

import * as THREE from 'three';
import { ENGINE } from '../data/constants.js';

// ── V4/PERF: retina-aware pixel-ratio cap (§E0.1-2 module-local tuning) ─────
// `ENGINE.MAX_PIXEL_RATIO` (2, frozen constants.js) stays the SAFE baseline:
// it is what software rasterizers (SwiftShader/llvmpipe VMs) keep. On real
// hardware GL the cap rises to 3 so DPR-3 phones (iPhone Pro class) render at
// native resolution instead of a blurry 2/3-width upscale. Only devices whose
// DPR actually exceeds 2 are affected — desktop DPR-1/2 output is unchanged.
export const RENDER_SCALE = Object.freeze({
  /** Pixel-ratio cap on hardware WebGL — full retina sharpness. */
  MAX_PIXEL_RATIO_HW: 3,
});

/**
 * Whether a WebGL renderer string names a software rasterizer (SwiftShader,
 * llvmpipe, softpipe, Microsoft Basic Render, "software renderer" ANGLE
 * spellings). Pure — same detection family as goobyWelt's splat guard, kept
 * module-local because core/ must not import game modules. Unknown/empty
 * strings return false (treat as hardware — the baseline cap still bounds it).
 * @param {string|null|undefined} rendererString GL renderer string
 * @returns {boolean}
 */
export function isSoftwareGl(rendererString) {
  if (typeof rendererString !== 'string' || rendererString === '') return false;
  return /swiftshader|llvmpipe|softpipe|software\s*(rasterizer|renderer|adapter)|microsoft basic render/i
    .test(rendererString);
}

/**
 * Effective renderer pixel ratio (pure decision, unit-tested): clamp the
 * device pixel ratio to `ENGINE.MAX_PIXEL_RATIO` on software GL (every extra
 * pixel is pure CPU cost there) and to `RENDER_SCALE.MAX_PIXEL_RATIO_HW` on
 * hardware GL. Non-finite/non-positive DPR inputs fall back to 1.
 * @param {number} dpr window.devicePixelRatio (may be undefined/garbage)
 * @param {boolean} softwareGl from isSoftwareGl(<GL renderer string>)
 * @returns {number}
 */
export function computePixelRatio(dpr, softwareGl) {
  const d = Number.isFinite(dpr) && dpr > 0 ? dpr : 1;
  const cap = softwareGl ? ENGINE.MAX_PIXEL_RATIO : RENDER_SCALE.MAX_PIXEL_RATIO_HW;
  return Math.min(d, cap);
}

/**
 * Read the unmasked GL renderer string off a live WebGLRenderer ('' when the
 * probe is unavailable — fails toward the hardware path, whose cap only
 * matters above DPR 2 anyway).
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
  // V4/PERF: retina-aware cap — hardware GL may go to 3 (native DPR-3 phones),
  // software GL (SwiftShader/llvmpipe) keeps the ENGINE.MAX_PIXEL_RATIO
  // baseline of 2, i.e. exactly the pre-V4 behavior on the headless VM.
  renderer.setPixelRatio(computePixelRatio(devicePixelRatio, isSoftwareGl(glRendererString(renderer))));
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
    renderer.setSize(innerWidth, innerHeight);
    const cam = current?.instance?.camera;
    if (cam && cam.isPerspectiveCamera) {
      cam.aspect = innerWidth / innerHeight;
      cam.updateProjectionMatrix();
    }
  }
  window.addEventListener('resize', onResize);

  // --- RAF loop ---
  let lastT = performance.now();
  function frame(t) {
    const dt = Math.min((t - lastT) / 1000, 0.1);
    lastT = t;
    const inst = current?.instance;
    if (inst) {
      try {
        inst.update?.(dt);
      } catch (err) {
        console.error('[sceneManager] scene update error:', err);
      }
      if (inst.scene && inst.camera) renderer.render(inst.scene, inst.camera);
    }
    requestAnimationFrame(frame);
  }
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
        const scopedInput = input.scoped();
        const ctx = { renderer, assets, input: scopedInput, audio, store, ui };
        const instance = entry.factory(ctx);
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
      } finally {
        switching = false;
      }
    },
  };

  return manager;
}
