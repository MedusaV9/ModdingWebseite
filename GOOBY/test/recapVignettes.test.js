// V4/G63 — recap biome vignettes: pure-side tests (PLAN4 §B5.4 + §C-SYS2.3).
// Covers the binding vignette-id order (== recapDirector.DEFAULT_BIOMES),
// the §C-SYS2.3 dolly/travel specs, the Catmull-Rom samplers, and that every
// preload key + backdrop file resolves to a COMMITTED asset on disk (the
// vignettes may only dress from existing kits — no new 3D assets).
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  VIGNETTE_IDS,
  VIGNETTE_SPECS,
  DRAW_CALL_BUDGET,
  BACKDROP,
  sampleSpline,
  dollyPose,
  goobyPose,
  clamp,
  // POLISH-J motion accents (pure samplers + per-biome rows)
  VIGNETTE_ACCENTS,
  flutterPose,
  driftPose,
  streakPose,
  // V6/B1 landscape framing contract (headless projection + seat/facing rules)
  LANDSCAPE_ASPECT,
  CENTER_SAFE,
  FACING,
  SEAT,
  wrapAngle,
  seatY,
  cameraBasis,
  projectPoint,
  goobyFrameNdc,
  goobyFacingYaw,
} from '../src/recap/vignettes.logic.js';
import {
  RECAP_BACKDROP_FILES,
  RECAP_ASSET_KEYS,
  RECAP_ASSET_KEYS_BY_BIOME,
} from '../src/recap/recapAssets.js';
import { DEFAULT_BIOMES } from '../src/systems/recapDirector.js';
import { PACK_FORMATS } from '../src/core/assets.js';

const publicDir = fileURLToPath(new URL('../public/', import.meta.url));

/** Mirror core/assets.getModelUrl → committed file path under public/. */
function modelPath(key) {
  const i = key.indexOf('/');
  const slug = key.slice(0, i);
  const name = key.slice(i + 1);
  const fmt = PACK_FORMATS[slug] ?? { root: 'kenney', ext: 'glb' };
  return `${publicDir}assets/${fmt.root}/${slug}/${name}.${fmt.ext}`;
}

// ---------------------------------------------------------------------------
// Binding id order (§C-SYS2.3 / G55 biomeOrder handshake)
// ---------------------------------------------------------------------------

test('VIGNETTE_IDS match recapDirector.DEFAULT_BIOMES ids in order (binding)', () => {
  assert.deepEqual([...VIGNETTE_IDS], DEFAULT_BIOMES.map((b) => b.id));
  assert.equal(VIGNETTE_IDS.length, 8);
});

test('every biome id has a spec, a backdrop file and a preload list', () => {
  for (const id of VIGNETTE_IDS) {
    assert.ok(VIGNETTE_SPECS[id], `spec for ${id}`);
    assert.ok(RECAP_BACKDROP_FILES[id], `backdrop for ${id}`);
    assert.ok(Array.isArray(RECAP_ASSET_KEYS_BY_BIOME[id]), `keys for ${id}`);
  }
  assert.deepEqual(Object.keys(VIGNETTE_SPECS), [...VIGNETTE_IDS]);
  assert.deepEqual(Object.keys(RECAP_BACKDROP_FILES), [...VIGNETTE_IDS]);
  assert.deepEqual(Object.keys(RECAP_ASSET_KEYS_BY_BIOME), [...VIGNETTE_IDS]);
});

// ---------------------------------------------------------------------------
// §C-SYS2.3 spec sanity (travel modes, durations, dolly shapes)
// ---------------------------------------------------------------------------

test('specs: travel modes are the §C-SYS2.3 journey kinds, durSec 8–12', () => {
  const allowed = new Set(['walk', 'drive', 'boat', 'fly', 'float']);
  for (const id of VIGNETTE_IDS) {
    const s = VIGNETTE_SPECS[id];
    assert.ok(allowed.has(s.travel), `${id} travel '${s.travel}'`);
    assert.ok(s.durSec >= 8 && s.durSec <= 12, `${id} durSec ${s.durSec}`);
    assert.ok(s.fov >= 40 && s.fov <= 60, `${id} fov`);
  }
  // binding table rows: city + toyRoom drive, harbor boats, space flies
  assert.equal(VIGNETTE_SPECS.city.travel, 'drive');
  assert.equal(VIGNETTE_SPECS.toyRoom.travel, 'drive');
  assert.equal(VIGNETTE_SPECS.harbor.travel, 'boat');
  assert.equal(VIGNETTE_SPECS.space.travel, 'fly');
  assert.equal(VIGNETTE_SPECS.nightSky.travel, 'float');
  // space's „gentle roll ±4°" is the only rolled dolly
  assert.equal(VIGNETTE_SPECS.space.rollAmpDeg, 4);
});

test('specs: dolly + gooby paths have ≥ 2 waypoints inside the backdrop', () => {
  const maxR = BACKDROP.RADIUS;
  for (const id of VIGNETTE_IDS) {
    const s = VIGNETTE_SPECS[id];
    for (const [name, path] of [['camPath', s.camPath], ['lookPath', s.lookPath], ['goobyPath', s.goobyPath]]) {
      assert.ok(path.length >= 2, `${id}.${name} length`);
      for (const p of path) {
        assert.equal(p.length, 3, `${id}.${name} triple`);
        assert.ok(Math.hypot(p[0], p[2]) < maxR, `${id}.${name} inside backdrop radius`);
        assert.ok(p[1] > -1 && p[1] < BACKDROP.CENTER_Y + BACKDROP.HEIGHT / 2, `${id}.${name} y sane`);
      }
    }
  }
});

test('dolly moves: camera or look travels ≥ 1.5 units per vignette', () => {
  for (const id of VIGNETTE_IDS) {
    const a = dollyPose(id, 0);
    const b = dollyPose(id, 1);
    const camDist = Math.hypot(
      b.position[0] - a.position[0], b.position[1] - a.position[1], b.position[2] - a.position[2]
    );
    const lookDist = Math.hypot(b.look[0] - a.look[0], b.look[1] - a.look[1], b.look[2] - a.look[2]);
    assert.ok(camDist + lookDist >= 1.5, `${id} dolly travels (${camDist.toFixed(2)} + ${lookDist.toFixed(2)})`);
  }
});

test('meadow dolly rises (the §C-SYS2.3 „12° rise" push-in)', () => {
  const start = dollyPose('meadow', 0);
  const end = dollyPose('meadow', 1);
  assert.ok(end.position[1] > start.position[1] + 1, 'camera rises');
  assert.ok(end.position[2] < start.position[2], 'camera pushes in');
});

test('harbor dolly orbits: heading around the boat changes ≥ 60°', () => {
  const a = dollyPose('harbor', 0);
  const b = dollyPose('harbor', 1);
  const angA = Math.atan2(a.position[0], a.position[2]);
  const angB = Math.atan2(b.position[0], b.position[2]);
  const sweep = Math.abs(angB - angA) * (180 / Math.PI);
  assert.ok(sweep >= 60, `orbit sweep ${sweep.toFixed(0)}°`);
});

test('nightSky dolly tilts up: look elevation climbs ≥ 25°', () => {
  const a = dollyPose('nightSky', 0);
  const b = dollyPose('nightSky', 1);
  const elev = (pose) => {
    const dx = pose.look[0] - pose.position[0];
    const dy = pose.look[1] - pose.position[1];
    const dz = pose.look[2] - pose.position[2];
    return Math.atan2(dy, Math.hypot(dx, dz)) * (180 / Math.PI);
  };
  assert.ok(elev(b) - elev(a) >= 25, `tilt-up ${(elev(b) - elev(a)).toFixed(1)}°`);
});

// ---------------------------------------------------------------------------
// Samplers (pure math)
// ---------------------------------------------------------------------------

test('sampleSpline passes through endpoints, clamps t, handles 2 points', () => {
  const pts = [[0, 0, 0], [1, 2, 3], [4, 4, 4]];
  assert.deepEqual(sampleSpline(pts, 0), [0, 0, 0]);
  assert.deepEqual(sampleSpline(pts, 1), [4, 4, 4]);
  assert.deepEqual(sampleSpline(pts, -5), [0, 0, 0]);
  assert.deepEqual(sampleSpline(pts, 5), [4, 4, 4]);
  const mid = sampleSpline([[0, 0, 0], [2, 0, 0]], 0.5);
  assert.ok(Math.abs(mid[0] - 1) < 1e-9, '2-point lerp');
  // degenerate inputs never throw
  assert.deepEqual(sampleSpline([], 0.5), [0, 0, 0]);
  assert.deepEqual(sampleSpline([[7, 8, 9]], 0.5), [7, 8, 9]);
});

test('sampleSpline is continuous across segment joins', () => {
  const pts = VIGNETTE_SPECS.meadow.camPath;
  let prev = sampleSpline(pts, 0);
  for (let i = 1; i <= 100; i++) {
    const cur = sampleSpline(pts, i / 100);
    const d = Math.hypot(cur[0] - prev[0], cur[1] - prev[1], cur[2] - prev[2]);
    assert.ok(d < 0.6, `step ${i} jump ${d}`);
    prev = cur;
  }
});

test('goobyPose: yaw faces along the path tangent; lead is applied+clamped', () => {
  const pose = goobyPose('city', 0.5); // city path runs +x → yaw ≈ +90°
  assert.ok(Math.abs(pose.yaw - Math.PI / 2) < 0.3, `city yaw ${pose.yaw}`);
  assert.ok(goobyPose('city', 1.2), 'over-progress clamps');
  assert.equal(goobyPose('nope', 0.5), null);
  assert.equal(dollyPose('nope', 0.5), null);
});

test('clamp + dollyPose roll: only space rolls, ±4° bounded', () => {
  assert.equal(clamp(5, 0, 1), 1);
  assert.equal(clamp(-5, 0, 1), 0);
  for (const id of VIGNETTE_IDS) {
    for (const p of [0, 0.25, 0.5, 0.75, 1]) {
      const { rollDeg } = dollyPose(id, p);
      assert.ok(Math.abs(rollDeg) <= 4 + 1e-9, `${id} roll bounded`);
      if (id !== 'space') assert.equal(rollDeg, 0, `${id} no roll`);
    }
  }
  assert.ok(Math.abs(dollyPose('space', 0.25).rollDeg - 4) < 1e-9, 'space peak roll +4°');
});

// ---------------------------------------------------------------------------
// Committed-asset resolution (existing kits ONLY — §C-SYS2.3)
// ---------------------------------------------------------------------------

test('every preload key resolves to a committed model file', () => {
  assert.ok(RECAP_ASSET_KEYS.length >= 60, `flat list has ${RECAP_ASSET_KEYS.length} keys`);
  for (const key of RECAP_ASSET_KEYS) {
    assert.match(key, /^[a-z0-9-]+\/[A-Za-z0-9_-]+$/, `key format ${key}`);
    assert.ok(existsSync(modelPath(key)), `committed file for ${key} (${modelPath(key)})`);
  }
});

test('flat preload list is the exact de-duplicated union of the biome lists', () => {
  const union = new Set(Object.values(RECAP_ASSET_KEYS_BY_BIOME).flat());
  assert.equal(RECAP_ASSET_KEYS.length, union.size, 'no dupes');
  assert.deepEqual([...new Set(RECAP_ASSET_KEYS)].sort(), [...union].sort());
});

test('all 8 ART-GATE-2 backdrop PNGs are committed', () => {
  for (const id of VIGNETTE_IDS) {
    const file = `${publicDir}assets/recap/${RECAP_BACKDROP_FILES[id]}`;
    assert.ok(existsSync(file), `backdrop ${RECAP_BACKDROP_FILES[id]}`);
  }
});

test('outfit continuity: the pumpkin outfit GLB rides the preload list', () => {
  // outfitAttach.OUTFIT_ASSET_KEYS's single GLB — keeps equipped pumpkin
  // hats placeholder-free in every vignette (see recapAssets.js header).
  assert.ok(RECAP_ASSET_KEYS.includes('kaykit-halloween/pumpkin_orange_small'));
});

test('perf gate constant: team budget 150 ≤ plan gate 250 (§B5.4)', () => {
  assert.equal(DRAW_CALL_BUDGET, 150);
  assert.ok(DRAW_CALL_BUDGET <= 250);
});

// ---------------------------------------------------------------------------
// Runtime registry integrity (source pins — vignettes.js imports three.js and
// the Gooby rig, so node pins the WIRING textually instead of importing it;
// same convention as the other scene-side suites)
// ---------------------------------------------------------------------------

const vignettesSrc = readFileSync(
  fileURLToPath(new URL('../src/recap/vignettes.js', import.meta.url)), 'utf8'
);

test('vignettes.js registry: every biome id wires a named builder (G64 contract)', () => {
  // one buildX function per biome, keyed in the frozen BUILDERS map
  const builders = {
    meadow: 'buildMeadow', city: 'buildCity', harbor: 'buildHarbor',
    space: 'buildSpace', spookGarden: 'buildSpookGarden', bakery: 'buildBakery',
    nightSky: 'buildNightSky', toyRoom: 'buildToyRoom',
  };
  assert.deepEqual(Object.keys(builders), [...VIGNETTE_IDS], 'pin covers the id order');
  const block = vignettesSrc.match(/const BUILDERS = Object\.freeze\(\{([^}]+)\}\)/);
  assert.ok(block, 'frozen BUILDERS map present');
  for (const [id, fn] of Object.entries(builders)) {
    assert.match(vignettesSrc, new RegExp(`function ${fn}\\(stage\\)`), `${fn}(stage) defined`);
    assert.match(block[1], new RegExp(`${id}: ${fn},`), `BUILDERS.${id} → ${fn}`);
  }
});

test('vignettes.js exports the stable G64 registry API surface', () => {
  for (const name of ['buildVignette', 'VIGNETTES', 'preloadBackdrops', 'backdropStatus']) {
    assert.match(vignettesSrc, new RegExp(`export (function |const )?${name}`), `export ${name}`);
  }
  // re-exported pure-side names ride along for one-import consumers
  assert.match(vignettesSrc, /export \{ VIGNETTE_IDS, VIGNETTE_SPECS, DRAW_CALL_BUDGET \};/);
  // VIGNETTES registry is generated from VIGNETTE_IDS (no hand-typed drift)
  assert.match(vignettesSrc, /VIGNETTE_IDS\.map\(\(id\) => \[/);
});

// ---------------------------------------------------------------------------
// POLISH-J — per-biome motion accents (pure rows + samplers). Decorative
// only: they ride the existing timeline and never touch cue timing.
// ---------------------------------------------------------------------------

test('POLISH-J accents: every biome defines ≥ 1 motion accent row', () => {
  assert.deepEqual(Object.keys(VIGNETTE_ACCENTS), [...VIGNETTE_IDS]);
  for (const id of VIGNETTE_IDS) {
    const a = VIGNETTE_ACCENTS[id];
    const n = a.flutters.length + a.drifts.length + a.streaks.length;
    assert.ok(n >= 1, `${id} has ${n} accent rows`);
  }
});

test('POLISH-J accents: sampled poses stay inside the backdrop, values sane', () => {
  for (const id of VIGNETTE_IDS) {
    const { flutters, drifts, streaks } = VIGNETTE_ACCENTS[id];
    for (const row of flutters) {
      for (const t of [0, 1.7, 5.3, 11.9]) {
        const pose = flutterPose(row, t);
        assert.ok(Math.hypot(pose.position[0], pose.position[2]) < BACKDROP.RADIUS,
          `${id} flutter inside backdrop at t=${t}`);
        assert.ok(pose.flap >= 0 && pose.flap <= 1, `${id} flap 0..1`);
      }
    }
    for (const row of drifts) {
      for (const t of [0, 2.2, 7.9]) {
        const pose = driftPose(row, t);
        assert.ok(Math.hypot(pose.position[0], pose.position[2]) < BACKDROP.RADIUS,
          `${id} drift inside backdrop at t=${t}`);
        assert.ok(pose.opacity >= 0 && pose.opacity <= row.opacity + 1e-9, `${id} drift opacity`);
        assert.ok(pose.grow >= 1, `${id} drift grows`);
      }
    }
    for (const row of streaks) {
      assert.ok(row.durFrac > 0 && row.durFrac < 1, `${id} streak durFrac`);
      for (const p of [row.from, row.to]) {
        assert.ok(Math.hypot(p[0], p[2]) < BACKDROP.RADIUS, `${id} streak inside backdrop`);
      }
    }
  }
});

test('POLISH-J flutterPose: deterministic orbit bounded by the row radius/bob', () => {
  const row = VIGNETTE_ACCENTS.meadow.flutters[0];
  assert.deepEqual(flutterPose(row, 1.25), flutterPose(row, 1.25));
  for (const t of [0.3, 0.8, 4.6]) {
    const pose = flutterPose(row, t);
    const dx = pose.position[0] - row.center[0];
    const dz = pose.position[2] - row.center[2];
    assert.ok(Math.hypot(dx, dz) <= row.radius + 1e-9, 'within orbit radius');
    assert.ok(Math.abs(pose.position[1] - row.center[1]) <= row.bob + 1e-9, 'bob bounded');
  }
});

test('POLISH-J driftPose: rises from origin, fades in from 0, peaks mid-loop', () => {
  const row = VIGNETTE_ACCENTS.bakery.drifts[0]; // phase 0 row
  const start = driftPose(row, 0);
  assert.ok(Math.abs(start.position[1] - row.origin[1]) < 1e-9, 'starts at origin height');
  assert.ok(start.opacity < 1e-9, 'fades in from 0');
  const mid = driftPose(row, 0.5 / row.speed);
  assert.ok(mid.position[1] > row.origin[1] + row.rise * 0.4, 'risen at mid-loop');
  assert.ok(Math.abs(mid.opacity - row.opacity) < 1e-6, 'peak opacity at mid-loop');
});

test('POLISH-J streakPose: inactive before delay, sweeps from→to in-window', () => {
  const row = VIGNETTE_ACCENTS.nightSky.streaks[0];
  assert.equal(streakPose(row, row.delay - 0.1).active, false);
  const winStart = streakPose(row, row.delay + 1e-6);
  assert.equal(winStart.active, true);
  for (let k = 0; k < 3; k++) {
    assert.ok(Math.abs(winStart.position[k] - row.from[k]) < 0.02, 'starts at from');
  }
  const mid = streakPose(row, row.delay + row.period * row.durFrac * 0.5);
  assert.equal(mid.active, true);
  assert.ok(mid.alpha > 0.9, 'bright mid-sweep');
  const after = streakPose(row, row.delay + row.period * row.durFrac + 0.05);
  assert.equal(after.active, false);
  assert.equal(after.alpha, 0);
});

test('POLISH-J wiring: vignettes.js builds + ticks the accent/particle layer', () => {
  assert.match(vignettesSrc, /function buildAccents\(stage\)/);
  assert.match(vignettesSrc, /const accents = buildAccents\(stage\)/);
  assert.match(vignettesSrc, /accents\.tick\(step\)/);
  assert.match(vignettesSrc, /stage\.tickParticles\(step\)/);
  // pooled accents come from the shared juice module (§G3), never a new dep
  assert.match(vignettesSrc, /import \{ createParticles \} from '\.\.\/gfx\/particles\.js'/);
});

test('dev harness surface: ?recappreview= param wired + documented', () => {
  const harnessSrc = readFileSync(
    fileURLToPath(new URL('../src/dev/harness.js', import.meta.url)), 'utf8'
  );
  assert.match(harnessSrc, /q\.get\('recappreview'\)/, 'harness reads the param');
  assert.match(harnessSrc, /recap\/vignettePreview\.js/, 'routes into the preview scene');
  const paramsSrc = readFileSync(
    fileURLToPath(new URL('../src/data/harnessParams.js', import.meta.url)), 'utf8'
  );
  assert.match(paramsSrc, /param: 'recappreview'/, 'dev-panel cheat sheet row present');
});

// ---------------------------------------------------------------------------
// V6/B1 — landscape framing contract (PLAN6 Wave B/B1). The recap renders a
// ROTATED landscape frame (LANDSCAPE_ASPECT ≈ 2.16 on the 390×844 reference
// phone), and camera pose + fov + aspect fully determine where Gooby lands —
// so the RC1 "Gooby out of frame" class of bug is pinned HEADLESSLY here.
// ---------------------------------------------------------------------------

test('V6/B1 projectPoint: pure PerspectiveCamera mirror (center/offsets/depth)', () => {
  const pose = { position: [0, 0, 5], look: [0, 0, 0], fov: 50 };
  const center = projectPoint(pose, LANDSCAPE_ASPECT, [0, 0, 0]);
  assert.ok(Math.abs(center.x) < 1e-9 && Math.abs(center.y) < 1e-9, 'look point → frame center');
  assert.ok(Math.abs(center.depth - 5) < 1e-9, 'view depth');
  assert.ok(projectPoint(pose, LANDSCAPE_ASPECT, [1, 0, 0]).x > 0, '+x → right of frame');
  assert.ok(projectPoint(pose, LANDSCAPE_ASPECT, [0, 1, 0]).y > 0, '+y → up in frame');
  assert.ok(projectPoint(pose, LANDSCAPE_ASPECT, [0, 0, 10]).depth < 0, 'behind → depth < 0');
  // wider aspect shrinks |x| for the same offset (horizontal fov grows)
  const wide = projectPoint(pose, 2.16, [1, 0, 0]);
  const narrow = projectPoint(pose, 0.46, [1, 0, 0]);
  assert.ok(wide.x < narrow.x, 'aspect widens the horizontal frame');
});

test('V6/B1 cameraBasis: orthonormal, faces the look point, roll spins the frame', () => {
  const pose = { position: [2, 1, 6], look: [-1, 2, -3], rollDeg: 0 };
  const { right, up, forward } = cameraBasis(pose);
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  for (const [name, v] of [['right', right], ['up', up], ['forward', forward]]) {
    assert.ok(Math.abs(Math.hypot(...v) - 1) < 1e-9, `${name} unit length`);
  }
  assert.ok(Math.abs(dot(right, up)) < 1e-9 && Math.abs(dot(right, forward)) < 1e-9
    && Math.abs(dot(up, forward)) < 1e-9, 'orthogonal basis');
  const rolled = cameraBasis({ ...pose, rollDeg: 30 });
  assert.ok(Math.abs(dot(rolled.forward, forward) - 1) < 1e-9, 'roll keeps the view axis');
  assert.ok(Math.abs(dot(rolled.right, right) - Math.cos(Math.PI / 6)) < 1e-9, 'roll angle exact');
});

test('V6/B1 CENTER-SAFE: Gooby projects inside the safe region in ALL 8 biomes', () => {
  // The binding B1 acceptance: across p ∈ {0.1,0.3,0.5,0.7,0.9} the body
  // center stays inside |x| ≤ CENTER_SAFE.X, |y| ≤ CENTER_SAFE.Y at the
  // landscape aspect — catches RC1 (city p→1 offscreen, bakery corner-clip,
  // spookGarden edge-pin) and any future spline retune that re-breaks it.
  for (const id of VIGNETTE_IDS) {
    for (const p of [0.1, 0.3, 0.5, 0.7, 0.9]) {
      const ndc = goobyFrameNdc(id, p);
      assert.ok(ndc, `${id} projects at p=${p}`);
      assert.ok(ndc.depth > 0.5, `${id} p=${p} Gooby in front of the camera (depth ${ndc.depth.toFixed(2)})`);
      assert.ok(Math.abs(ndc.x) <= CENTER_SAFE.X, `${id} p=${p} x ${ndc.x.toFixed(2)} inside ±${CENTER_SAFE.X}`);
      assert.ok(Math.abs(ndc.y) <= CENTER_SAFE.Y, `${id} p=${p} y ${ndc.y.toFixed(2)} inside ±${CENTER_SAFE.Y}`);
    }
  }
  assert.equal(goobyFrameNdc('nope', 0.5), null);
});

test('V6/B1 RC1 fix pinned: crop-push goobyLead zeroed on city/bakery/toyRoom', () => {
  assert.ok(Math.abs(LANDSCAPE_ASPECT - 844 / 390) < 1e-9, 'reference frame 844×390');
  assert.equal(VIGNETTE_SPECS.city.goobyLead, 0);
  assert.equal(VIGNETTE_SPECS.bakery.goobyLead, 0);
  assert.equal(VIGNETTE_SPECS.toyRoom.goobyLead, 0);
});

test('V6/B1 seatY (RC2): measured hull top − sink; a "lift" can never hover', () => {
  assert.ok(Math.abs(seatY(0.32) - (0.32 - SEAT.SINK)) < 1e-9);
  assert.ok(Math.abs(seatY(0.32, 0.1) - 0.22) < 1e-9);
  // negative sink clamps to 0 — seating ABOVE the measured top would
  // reintroduce exactly the RC2 mid-air hover this rule exists to kill
  assert.ok(Math.abs(seatY(0.2, -0.1) - 0.2) < 1e-9, 'negative sink clamps');
  assert.ok(Math.abs(seatY(NaN) - -SEAT.SINK) < 1e-9, 'junk top folds to 0');
  assert.ok(Math.abs(seatY(0.5, NaN) - (0.5 - SEAT.SINK)) < 1e-9, 'junk sink → default');
});

test('V6/B1 wrapAngle: wraps into [−π, π)', () => {
  assert.ok(Math.abs(wrapAngle(3 * Math.PI) - -Math.PI) < 1e-9);
  assert.ok(Math.abs(wrapAngle(2 * Math.PI)) < 1e-9);
  assert.ok(Math.abs(wrapAngle(-Math.PI / 2) - -Math.PI / 2) < 1e-9);
  assert.equal(wrapAngle(undefined), 0);
});

test('V6/B1 facing bias: walk-biome Gooby is never fully back-to-camera', () => {
  // Invariant: the biased yaw never points farther from the camera than the
  // raw tangent, and the residual away-angle is bounded by π·(1 − MAX_BIAS)
  // (< AWAY_START poses pass through un-biased — bound holds trivially; the
  // ramp's interior maximum sits ~5e-6 above the endpoint, hence the slack).
  const bound = Math.PI * (1 - FACING.MAX_BIAS) + 1e-4;
  let engaged = 0;
  for (const id of ['meadow', 'spookGarden', 'bakery']) {
    assert.equal(VIGNETTE_SPECS[id].travel, 'walk', `${id} is a walk biome`);
    for (let i = 0; i <= 20; i++) {
      const p = i / 20;
      const f = goobyFacingYaw(id, p);
      assert.ok(f, `${id} p=${p} resolves`);
      const rawAway = Math.abs(wrapAngle(f.toCam - f.tangentYaw));
      const biasedAway = Math.abs(wrapAngle(f.toCam - f.yaw));
      assert.ok(biasedAway <= rawAway + 1e-9, `${id} p=${p} bias never turns him further away`);
      assert.ok(biasedAway <= bound, `${id} p=${p} residual away ${biasedAway.toFixed(2)} ≤ ${bound.toFixed(2)}`);
      assert.ok(f.bias >= 0 && f.bias <= FACING.MAX_BIAS + 1e-9, `${id} bias 0..MAX`);
      if (rawAway < FACING.AWAY_START_RAD) {
        assert.ok(Math.abs(wrapAngle(f.yaw - f.tangentYaw)) < 1e-9, `${id} p=${p} no bias while facing`);
      } else if (f.bias > 1e-6) {
        engaged += 1;
      }
    }
  }
  assert.ok(engaged > 0, 'the bias actually engages somewhere on the walk paths');
  assert.equal(goobyFacingYaw('nope', 0.5), null);
});

test('V6/B1 wiring pins: measured seats + facing bias land in vignettes.js', () => {
  // RC2 — the space seat comes from the speeder's MEASURED Box3 top; the
  // old hard-coded hover constant must be gone.
  assert.match(vignettesSrc, /new THREE\.Box3\(\)\.setFromObject\(speeder\)\.max\.y/);
  assert.match(vignettesSrc, /gooby\.group\.position\.set\(0, seatY\(hullTop\), 0\.35\)/);
  assert.doesNotMatch(vignettesSrc, /gooby\.group\.position\.set\(0, 0\.42/);
  // city sunroof + toyRoom cockpit ride their existing wheel-placement Box3
  assert.match(vignettesSrc, /seatY\(box\.max\.y, 0\.15\)/);
  assert.match(vignettesSrc, /seatY\(box\.max\.y\), -0\.02/);
  // RC1 — all three walk ticks apply the face-the-camera bias
  for (const id of ['meadow', 'spookGarden', 'bakery']) {
    assert.match(vignettesSrc, new RegExp(`goobyFacingYaw\\('${id}', p\\)`), `${id} tick biased`);
  }
  assert.match(vignettesSrc, /seatY, goobyFacingYaw,\r?\n\} from '\.\/vignettes\.logic\.js'/);
  // Landscape-exposed bg-clobber guard: the player defers the outgoing
  // vignette's dispose past the cut, so dispose may only restore
  // scene.background while it is still ITS OWN instance — the wide landscape
  // frustum sees past the backdrop cylinder where a stale color would show.
  assert.match(vignettesSrc, /const myBackground = new THREE\.Color\(spec\.bg\)/);
  assert.match(
    vignettesSrc,
    /if \(scene\.background === myBackground\) scene\.background = prevBackground;/,
    'dispose restores the background only when still its own'
  );
});
