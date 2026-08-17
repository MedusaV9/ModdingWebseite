// V6/E1 — Funkelpark plaza layout (PLAN6 Wave E/E1, risk row 6): pure
// headless checks on park/parkBuilder.js — the ZERO-OVERLAP acceptance test
// (AABB footprints, many seeds), seeded determinism with FIXED integration
// anchors (E3's Candy Alley strip, E2's coaster kiosk, F4's reserved
// ferrisWheel), plaza-bounds containment, and Gooby's stroll loop staying
// clear of every placed footprint.
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  PARK_PLAZA,
  PARK_ASSET_KEYS,
  itemsOverlap,
  overlappingPairs,
  generateParkLayout,
} from '../src/park/parkBuilder.js';
import { PARK_DRESSING } from '../src/park/parkDressing.js'; // E3's measured strip
import { DRIVE_TUNING } from '../src/data/constants.js';

const SEED = DRIVE_TUNING.CITY_SEED; // the plaza players actually visit
const SEEDS = Array.from({ length: 20 }, (_, i) => SEED + i);

// ------------------------------------------------------------- determinism

test('same seed → byte-identical plaza layout', () => {
  assert.deepEqual(generateParkLayout(SEED), generateParkLayout(SEED));
});

test('different seeds → jittered rim greenery, IDENTICAL fixed anchors/paths', () => {
  const a = generateParkLayout(SEED);
  const b = generateParkLayout(SEED + 5);
  // the integration anchors are hand-placed, never seeded (frozen contract:
  // E3's alley, E2's kiosk, F4's ferrisWheel reserve mount at fixed spots)
  assert.deepEqual(a.anchors, b.anchors);
  assert.deepEqual(a.paths, b.paths);
  assert.deepEqual(a.entry, b.entry);
  assert.deepEqual(a.goobyPath, b.goobyPath);
  // …while the seeded rim differs (tree ring jitter/pick)
  const treesOf = (l) => l.items.filter((i) => i.kind === 'tree');
  assert.notEqual(JSON.stringify(treesOf(a)), JSON.stringify(treesOf(b)));
});

// ------------------------------------------------- zero-overlap (risk row 6)

test('itemsOverlap: strict AABB — overlaps hit, touching edges are allowed', () => {
  const at = (x, z, hw, hd) => ({ x, z, hw, hd });
  assert.equal(itemsOverlap(at(0, 0, 2, 2), at(3, 0, 2, 2)), true); // 1 m bite
  assert.equal(itemsOverlap(at(0, 0, 2, 2), at(4, 0, 2, 2)), false); // kissing edges
  assert.equal(itemsOverlap(at(0, 0, 2, 2), at(0, 4.5, 2, 2)), false); // clear on z
  assert.equal(itemsOverlap(at(0, 0, 2, 2), at(1, 1, 0.5, 0.5)), true); // contained
});

test('ZERO overlapping footprint pairs — 20 seeds (the acceptance check)', () => {
  for (const seed of SEEDS) {
    assert.deepEqual(
      overlappingPairs(generateParkLayout(seed)),
      [],
      `seed ${seed} placed overlapping footprints`
    );
  }
});

test('every footprint stays fully inside the ±HALF plaza bounds (20 seeds)', () => {
  for (const seed of SEEDS) {
    const layout = generateParkLayout(seed);
    assert.equal(layout.half, PARK_PLAZA.HALF);
    for (const it of layout.items) {
      assert.ok(
        Math.abs(it.x) + it.hw <= layout.half + 1e-9 &&
          Math.abs(it.z) + it.hd <= layout.half + 1e-9,
        `seed ${seed}: ${it.id} footprint leaves the plaza`
      );
    }
  }
});

test('item ids stay unique and every GLB key is in PARK_ASSET_KEYS (20 seeds)', () => {
  const keys = new Set(PARK_ASSET_KEYS);
  for (const seed of SEEDS) {
    const layout = generateParkLayout(seed);
    assert.equal(new Set(layout.items.map((i) => i.id)).size, layout.items.length);
    for (const it of layout.items) {
      if (it.key !== null) assert.ok(keys.has(it.key), `${it.key} not preloadable`);
    }
  }
});

// ------------------------------------------- integration anchors (Wave E)

test('anchors: gate/candyAlley/coasterKiosk/ferrisWheel/fountain all placed as items', () => {
  const layout = generateParkLayout(SEED);
  for (const name of ['gate', 'candyAlley', 'coasterKiosk', 'ferrisWheel', 'fountain']) {
    const anchor = layout.anchors[name];
    assert.ok(anchor, `anchor ${name} missing`);
    assert.ok(layout.items.includes(anchor), `anchor ${name} not in items[]`);
  }
  // the gate guards the south edge (trip arrivals walk in heading north)
  assert.ok(layout.anchors.gate.z > 0, 'gate on the south (+z) edge');
  assert.equal(layout.anchors.gate.key, 'minigolf-kit/castle');
  // Gooby spawns just inside the gate, between gate front and fountain
  assert.ok(layout.entry.z < layout.anchors.gate.z - layout.anchors.gate.hd);
});

test("candyAlley footprint == E3's measured 13.1×2.9 strip (rotY 90° swaps axes)", () => {
  const alley = generateParkLayout(SEED).anchors.candyAlley;
  assert.equal(alley.key, null); // E3's mountParkDressing owns the visuals
  assert.equal(alley.hw * 2, PARK_DRESSING.FOOTPRINT.depth);
  assert.equal(alley.hd * 2, PARK_DRESSING.FOOTPRINT.width);
  assert.equal(alley.rotY, Math.PI / 2); // stalls face east into the plaza
});

test('ferrisWheel reserve (F4): named anchor, deliberately EMPTY, footprint kept clear', () => {
  for (const seed of SEEDS) {
    const layout = generateParkLayout(seed);
    const wheel = layout.anchors.ferrisWheel;
    assert.equal(wheel.kind, 'reserved');
    assert.equal(wheel.key, null); // nothing mounts there until F4
    for (const it of layout.items) {
      if (it === wheel) continue;
      assert.ok(!itemsOverlap(it, wheel), `seed ${seed}: ${it.id} invades F4's reserve`);
    }
  }
});

// ------------------------------------------------------- paths + Gooby loop

test('path ribbons: ≥ 2 points each, positive width, endpoints inside the plaza', () => {
  const layout = generateParkLayout(SEED);
  assert.ok(layout.paths.length >= 4); // spine + alley + coaster + wheel approach
  for (const path of layout.paths) {
    assert.ok(path.pts.length >= 2, `${path.id} needs a polyline`);
    assert.ok(path.width > 0);
    for (const p of path.pts) {
      assert.ok(Math.abs(p.x) <= layout.half && Math.abs(p.z) <= layout.half);
    }
  }
});

test("Gooby's entry + stroll loop never stand inside a placed footprint (20 seeds)", () => {
  for (const seed of SEEDS) {
    const layout = generateParkLayout(seed);
    for (const p of [layout.entry, ...layout.goobyPath]) {
      for (const it of layout.items) {
        assert.ok(
          !(Math.abs(p.x - it.x) < it.hw && Math.abs(p.z - it.z) < it.hd),
          `seed ${seed}: stroll point (${p.x},${p.z}) inside ${it.id}`
        );
      }
    }
  }
});
