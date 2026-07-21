/**
 * GOOBY — V4/PERF + V4/FIX-SM core tests: the retina-aware pixel-ratio
 * decision (conservative-by-default GL classification), the crash-proof RAF
 * frame runner, the failed-switch teardown helper (src/core/sceneManager.js
 * pure exports) and the asset-cache fast path (src/core/assets.js load-time
 * skinned probe).
 *
 * Pure node:test — sceneManager.js is import-safe under node (its module
 * scope has no DOM access; createSceneManager is never called here).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { ENGINE } from '../src/data/constants.js';
import {
  RENDER_SCALE,
  isSoftwareGl,
  classifyGlRenderer,
  computePixelRatio,
  createFrameRunner,
  disposeFailedSwitch,
} from '../src/core/sceneManager.js';

// ---------------------------------------------------------------------------
// V4/PERF: RENDER_SCALE + isSoftwareGl + computePixelRatio (§E0.1-2 pattern —
// the engine tuning const lives frozen INSIDE sceneManager.js, constants.js
// stays frozen at MAX_PIXEL_RATIO 2 as the safe software-GL baseline).
// ---------------------------------------------------------------------------

test('V4/PERF: RENDER_SCALE is frozen and only ever RAISES the baseline cap', () => {
  assert.ok(Object.isFrozen(RENDER_SCALE), 'RENDER_SCALE must be frozen');
  assert.equal(RENDER_SCALE.MAX_PIXEL_RATIO_HW, 3);
  assert.ok(
    RENDER_SCALE.MAX_PIXEL_RATIO_HW >= ENGINE.MAX_PIXEL_RATIO,
    'hardware cap must never drop below the frozen ENGINE baseline'
  );
});

test('V4/PERF: isSoftwareGl flags software rasterizer strings only', () => {
  const software = [
    'Google SwiftShader',
    'ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (Subzero) (0x0000C0DE)), SwiftShader driver)',
    'llvmpipe (LLVM 15.0.7, 256 bits)',
    'softpipe',
    'Microsoft Basic Render Driver',
    'Software Rasterizer',
    'ANGLE (Software Adapter, Direct3D11)',
  ];
  for (const s of software) assert.equal(isSoftwareGl(s), true, `software: ${s}`);
  const hardware = [
    'Apple GPU',
    'Apple A17 Pro GPU',
    'ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)',
    'Adreno (TM) 740',
    'Mali-G78',
    'NVIDIA GeForce RTX 3080/PCIe/SSE2',
    'AMD Radeon Pro 5500M OpenGL Engine',
  ];
  for (const s of hardware) assert.equal(isSoftwareGl(s), false, `hardware: ${s}`);
  // unknown/absent probes fail toward the hardware path (the cap still bounds)
  assert.equal(isSoftwareGl(''), false);
  assert.equal(isSoftwareGl(null), false);
  assert.equal(isSoftwareGl(undefined), false);
});

test('V4/FIX-SM: classifyGlRenderer — software / hardware / unknown three-way split', () => {
  const software = [
    'Google SwiftShader',
    'ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (Subzero) (0x0000C0DE)), SwiftShader driver)',
    'llvmpipe (LLVM 15.0.7, 256 bits)',
    'Microsoft Basic Render Driver',
    'ANGLE (Software Adapter, Direct3D11)',
  ];
  for (const s of software) assert.equal(classifyGlRenderer(s), 'software', `software: ${s}`);
  const hardware = [
    'Apple GPU',
    'Apple A17 Pro GPU',
    'ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)',
    'Adreno (TM) 740',
    'Mali-G78',
    'ARM Immortalis-G720',
    'Samsung Xclipse 940',
    'PowerVR Rogue GE8320',
    'NVIDIA GeForce RTX 3080/PCIe/SSE2',
    'AMD Radeon Pro 5500M OpenGL Engine',
    'ANGLE (Intel, Intel(R) Iris(R) Xe Graphics Direct3D11 vs_5_0 ps_5_0)',
  ];
  for (const s of hardware) assert.equal(classifyGlRenderer(s), 'hardware', `hardware: ${s}`);
  // empty/absent probes and unrecognized GPU strings are UNKNOWN — they must
  // NOT fail open into the DPR-3 hardware path (V4/FIX-SM defect 4)
  const unknown = ['', '   ', null, undefined, 'WebKit WebGL', 'Generic GPU Device 0x1234'];
  for (const s of unknown) assert.equal(classifyGlRenderer(s), 'unknown', `unknown: ${s}`);
});

test('V4/FIX-SM: computePixelRatio — retina bump ONLY on explicit hardware', () => {
  // DPR-3 iPhone: explicit hardware GL renders native; software keeps the cap
  assert.equal(computePixelRatio(3, 'hardware'), 3);
  assert.equal(computePixelRatio(3, 'software'), ENGINE.MAX_PIXEL_RATIO);
  // above-cap DPRs clamp to the respective cap
  assert.equal(computePixelRatio(4, 'hardware'), RENDER_SCALE.MAX_PIXEL_RATIO_HW);
  assert.equal(computePixelRatio(4, 'software'), ENGINE.MAX_PIXEL_RATIO);
  // DPR ≤ 2 is IDENTICAL on all paths — no behavior change for desktops,
  // DPR-2 phones, or the headless VM (devicePixelRatio 1 there)
  for (const dpr of [1, 1.5, 2]) {
    for (const cls of ['hardware', 'software', 'unknown']) {
      assert.equal(computePixelRatio(dpr, cls), dpr, `${cls} dpr=${dpr}`);
    }
  }
  // fractional Android DPRs between 2 and 3 go native on explicit hardware only
  assert.equal(computePixelRatio(2.625, 'hardware'), 2.625);
  assert.equal(computePixelRatio(2.625, 'software'), 2);
});

test('V4/FIX-SM: unknown/ambiguous GL class defaults CONSERVATIVE (cap 2, never 3)', () => {
  // the fail-open bug: unknown renderer strings used to be treated as
  // hardware → DPR 3 → 2.25× the pixels on unidentifiable GPUs
  assert.equal(computePixelRatio(3, 'unknown'), ENGINE.MAX_PIXEL_RATIO);
  assert.equal(computePixelRatio(4, 'unknown'), ENGINE.MAX_PIXEL_RATIO);
  assert.equal(computePixelRatio(2.625, 'unknown'), ENGINE.MAX_PIXEL_RATIO);
  // garbage classifications fail closed too — anything not exactly
  // 'hardware' keeps the frozen baseline
  for (const cls of [undefined, null, '', 'HARDWARE', 'hw', true, 42]) {
    assert.equal(computePixelRatio(3, cls), ENGINE.MAX_PIXEL_RATIO, `class=${String(cls)}`);
  }
  // end-to-end: an unknown probe string classifies to the conservative cap
  assert.equal(computePixelRatio(3, classifyGlRenderer('')), 2);
  assert.equal(computePixelRatio(3, classifyGlRenderer('Generic GPU Device 0x1234')), 2);
});

test('V4/PERF: computePixelRatio survives garbage DPR inputs', () => {
  for (const bad of [0, -2, NaN, Infinity, -Infinity, undefined, null]) {
    assert.equal(computePixelRatio(bad, 'hardware'), 1, `hw dpr=${bad}`);
    assert.equal(computePixelRatio(bad, 'software'), 1, `sw dpr=${bad}`);
    assert.equal(computePixelRatio(bad, 'unknown'), 1, `unknown dpr=${bad}`);
  }
});

// ---------------------------------------------------------------------------
// V4/FIX-SM: crash-proof RAF loop (createFrameRunner). The next frame must be
// scheduled BEFORE the scene's update/render run, and both update() and
// render() are guarded independently — one throw must never kill the loop.
// ---------------------------------------------------------------------------

test('V4/FIX-SM: frame runner schedules the NEXT frame before update/render', () => {
  /** @type {string[]} */
  const order = [];
  const frame = createFrameRunner({
    schedule: () => order.push('schedule'),
    getInstance: () => ({
      update: () => order.push('update'),
      scene: {},
      camera: {},
    }),
    render: () => order.push('render'),
  });
  frame(16);
  assert.deepEqual(order, ['schedule', 'update', 'render']);
});

test('V4/FIX-SM: the loop survives a throwing update() AND still renders', (t) => {
  const mocked = t.mock.method(console, 'error', () => {});
  try {
    let scheduled = 0;
    let rendered = 0;
    const frame = createFrameRunner({
      schedule: () => {
        scheduled += 1;
      },
      getInstance: () => ({
        update: () => {
          throw new Error('scene update boom');
        },
        scene: {},
        camera: {},
      }),
      render: () => {
        rendered += 1;
      },
    });
    frame(16);
    frame(32);
    assert.equal(scheduled, 2, 'every frame reschedules despite the update throw');
    assert.equal(rendered, 2, 'a bad update must not block rendering');
    assert.ok(mocked.mock.callCount() >= 2, 'update errors are logged, not swallowed silently');
  } finally {
    mocked.mock.restore();
  }
});

test('V4/FIX-SM: the loop survives a throwing render() — the S1 freeze bug', (t) => {
  const mocked = t.mock.method(console, 'error', () => {});
  try {
    let scheduled = 0;
    let updates = 0;
    const frame = createFrameRunner({
      schedule: () => {
        scheduled += 1;
      },
      getInstance: () => ({
        update: () => {
          updates += 1;
        },
        scene: {},
        camera: {},
      }),
      render: () => {
        throw new Error('renderer.render boom (context loss)');
      },
    });
    // before the fix, ONE render throw skipped the reschedule → permanent freeze
    frame(16);
    frame(32);
    frame(48);
    assert.equal(scheduled, 3, 'the loop must reschedule through every render throw');
    assert.equal(updates, 3, 'scene updates keep running');
    assert.ok(mocked.mock.callCount() >= 3, 'render errors are logged');
  } finally {
    mocked.mock.restore();
  }
});

test('V4/FIX-SM: frame runner clamps dt to 100 ms and skips render without scene/camera', () => {
  /** @type {number[]} */
  const dts = [];
  let rendered = 0;
  let inst = { update: (dt) => dts.push(dt), scene: {}, camera: {} };
  const frame = createFrameRunner({
    schedule: () => {},
    getInstance: () => inst,
    render: () => {
      rendered += 1;
    },
    initialT: 0,
  });
  frame(16); // 16 ms → 0.016 s
  frame(5016); // 5 s hitch → clamped to 0.1 s
  assert.equal(dts.length, 2);
  assert.ok(Math.abs(dts[0] - 0.016) < 1e-9, `dt=${dts[0]}`);
  assert.equal(dts[1], 0.1, 'hitched frames clamp to 100 ms');
  assert.equal(rendered, 2);
  // scene/camera missing → update still runs, render is skipped
  inst = { update: (dt) => dts.push(dt) };
  frame(5032);
  assert.equal(dts.length, 3);
  assert.equal(rendered, 2, 'no render without scene+camera');
  // no instance at all → nothing runs, no throw
  inst = null;
  frame(5048);
  assert.equal(dts.length, 3);
  assert.equal(rendered, 2);
});

// ---------------------------------------------------------------------------
// V4/FIX-SM: failed-switch teardown (disposeFailedSwitch) — the helper behind
// switchTo's fade recovery. It must run every step, await async disposes and
// NEVER throw, so switchTo can always lift the black overlay afterwards.
// ---------------------------------------------------------------------------

test('V4/FIX-SM: disposeFailedSwitch runs exit → dispose → input release in order', async () => {
  /** @type {string[]} */
  const order = [];
  await disposeFailedSwitch(
    {
      exit: () => order.push('exit'),
      dispose: async () => {
        await Promise.resolve();
        order.push('dispose');
      },
      scene: {},
      camera: {},
    },
    { removeAll: () => order.push('removeAll') }
  );
  assert.deepEqual(order, ['exit', 'dispose', 'removeAll'], 'async dispose is AWAITED before input release');
});

test('V4/FIX-SM wiring: switchTo recovery + context-loss listeners pinned at source', async () => {
  const fs = await import('node:fs');
  const url = await import('node:url');
  const sm = fs.readFileSync(
    url.fileURLToPath(new URL('../src/core/sceneManager.js', import.meta.url)),
    'utf8'
  );
  // defect 2: the failed-switch catch disposes the partial instance, LIFTS
  // the black fade, then rethrows — in that order
  assert.match(
    sm,
    /catch \(err\) \{[\s\S]{0,1500}?await disposeFailedSwitch\(instance, scopedInput\);\s*\r?\n\s*await fadeTo\(0\);\s*\r?\n\s*throw err;/,
    'switchTo error path must dispose, reveal (fadeTo(0)), then rethrow'
  );
  // defect 1: production loop is built from the crash-proof runner
  assert.match(sm, /createFrameRunner\(\{[\s\S]{0,300}?schedule: \(cb\) => requestAnimationFrame\(cb\)/);
  // defect 3: manager-level context-loss listeners on the shared canvas
  assert.match(sm, /canvas\.addEventListener\('webglcontextlost', onContextLost\)/);
  assert.match(sm, /canvas\.addEventListener\('webglcontextrestored', onContextRestored\)/);
  assert.match(sm, /e\?\.preventDefault\?\.\(\);/, 'lost handler must preventDefault so restore can happen');
});

test('V4/FIX-SM: disposeFailedSwitch never throws — partial/broken instances included', async (t) => {
  const mocked = t.mock.method(console, 'error', () => {});
  try {
    // null instance (factory threw before returning) + null input scope
    await disposeFailedSwitch(null, null);
    await disposeFailedSwitch(undefined, undefined);
    // every step throwing must still reach the next one
    let removed = 0;
    await disposeFailedSwitch(
      {
        exit: () => {
          throw new Error('exit boom');
        },
        dispose: () => Promise.reject(new Error('dispose boom')),
      },
      {
        removeAll: () => {
          removed += 1;
          throw new Error('removeAll boom');
        },
      }
    );
    assert.equal(removed, 1, 'input release still attempted after exit/dispose throws');
    assert.equal(mocked.mock.callCount(), 3, 'each failed step is logged');
  } finally {
    mocked.mock.restore();
  }
});

// ---------------------------------------------------------------------------
// V4/PERF: assets.js — the SkinnedMesh probe moved to LOAD time. getModel
// used to re-traverse the whole master hierarchy on EVERY cache hit (every
// room prop / food placement) just to decide whether to warn.
// ---------------------------------------------------------------------------

test('V4/PERF: getModel cache hits do not re-traverse the master', async (t) => {
  const assets = await import('../src/core/assets.js');
  t.after(() => assets._setLoaderForTests(null));

  const key = 'food-kit/__v4perf-traverse-test';
  let traversals = 0;
  const master = {
    name: 'master',
    traverse() {
      traversals += 1;
    },
    clone() {
      return { name: '' };
    },
  };
  assets._setLoaderForTests({ loadAsync: () => Promise.resolve({ scene: master }) });
  await assets.preload([key]);
  const atLoad = traversals;
  assert.ok(atLoad >= 1, 'load-time normalization + skinned probe walk the master once');
  for (let i = 0; i < 32; i += 1) {
    assert.equal(assets.getModel(key).name, key, 'clones still served');
  }
  assert.equal(
    traversals,
    atLoad,
    'getModel must serve clones without re-walking the master hierarchy'
  );
});

test('V4/PERF: the §B6 skinned warning still fires from the cached flag', async (t) => {
  const assets = await import('../src/core/assets.js');
  const THREE = await import('three');
  t.after(() => assets._setLoaderForTests(null));

  const skinnedKey = 'kaykit-characters/__v4perf-skinned-warn-test';
  const scene = new THREE.Group();
  const meshish = new THREE.Object3D();
  meshish.isSkinnedMesh = true; // the probe only checks the flag
  scene.add(meshish);
  assets._setLoaderForTests({ loadAsync: () => Promise.resolve({ scene, animations: [] }) });
  await assets.preload([skinnedKey]);

  const staticKey = 'food-kit/__v4perf-static-nowarn-test';
  assets._setLoaderForTests({
    loadAsync: () => Promise.resolve({ scene: new THREE.Group() }),
  });
  await assets.preload([staticKey]);

  /** @type {string[]} */
  const warns = [];
  const mocked = t.mock.method(console, 'warn', (...args) => {
    warns.push(args.join(' '));
  });
  try {
    assert.equal(assets.getModel(skinnedKey).name, skinnedKey);
    assert.ok(
      warns.some((m) => m.includes('getSkinnedModel')),
      'skinned-model misuse warning preserved'
    );
    warns.length = 0;
    assert.equal(assets.getModel(staticKey).name, staticKey);
    assert.deepEqual(warns, [], 'static models must not warn on cache hits');
  } finally {
    mocked.mock.restore();
  }
});
