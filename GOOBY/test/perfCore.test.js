/**
 * GOOBY — V4/PERF core tests: the retina-aware pixel-ratio decision
 * (src/core/sceneManager.js pure exports) and the asset-cache fast path
 * (src/core/assets.js load-time skinned probe).
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
  computePixelRatio,
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

test('V4/PERF: computePixelRatio — retina bump on hardware, baseline on software', () => {
  // DPR-3 iPhone: hardware GL renders native; software GL keeps the old cap
  assert.equal(computePixelRatio(3, false), 3);
  assert.equal(computePixelRatio(3, true), ENGINE.MAX_PIXEL_RATIO);
  // above-cap DPRs clamp to the respective cap
  assert.equal(computePixelRatio(4, false), RENDER_SCALE.MAX_PIXEL_RATIO_HW);
  assert.equal(computePixelRatio(4, true), ENGINE.MAX_PIXEL_RATIO);
  // DPR ≤ 2 is IDENTICAL on both paths — no behavior change for desktops,
  // DPR-2 phones, or the headless VM (devicePixelRatio 1 there)
  for (const dpr of [1, 1.5, 2]) {
    assert.equal(computePixelRatio(dpr, false), dpr, `hw dpr=${dpr}`);
    assert.equal(computePixelRatio(dpr, true), dpr, `sw dpr=${dpr}`);
  }
  // fractional Android DPRs between 2 and 3 go native on hardware only
  assert.equal(computePixelRatio(2.625, false), 2.625);
  assert.equal(computePixelRatio(2.625, true), 2);
});

test('V4/PERF: computePixelRatio survives garbage DPR inputs', () => {
  for (const bad of [0, -2, NaN, Infinity, -Infinity, undefined, null]) {
    assert.equal(computePixelRatio(bad, false), 1, `hw dpr=${bad}`);
    assert.equal(computePixelRatio(bad, true), 1, `sw dpr=${bad}`);
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
