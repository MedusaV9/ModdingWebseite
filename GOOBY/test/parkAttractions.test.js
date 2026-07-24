// V6/E3 (PLAN6 Wave E) — Funkelpark Candy Alley contract tests: park-food
// catalog completeness + anti-undercut price floors, the shop-hiding filter
// contract, the buy→tray→feed path (unchanged economy.buyFood), the pure
// bounds-grounding/bunting helpers, the band-swap bookkeeping model (night
// layer ≤ 2 added draw calls), and v6-park.js EN/DE parity incl. E2's
// caption block.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { createStore } from '../src/core/store.js';
import { defaultState } from '../src/core/save.js';
import { FOODS, V6_PARK_FOODS, getFood } from '../src/data/foods.js';
import { buyFood } from '../src/systems/economy.js';
import { count as invCount } from '../src/systems/inventory.js';
import { feedGooby } from '../src/home/interactions.js';
import {
  PARK_DRESSING,
  PARK_STALLS,
  PARK_DRESSING_ASSET_KEYS,
  NIGHT_LAYER_DRAW_CALLS,
  groundOffset,
  counterPlaneZ,
  buntingPoints,
  buntingSpots,
  bandVisual,
  swapPlan,
} from '../src/park/parkDressing.js';
import { PARK_FOOD_ICON_FALLBACK, parkFoodIcon } from '../src/ui/parkStall.js';
import { foodIconIds } from '../src/ui/foodIcons.js';
import { EN as PARK_EN, DE as PARK_DE } from '../src/data/strings/v6-park.js';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

// ---------------------------------------------------------------------------
// Park foods: catalog completeness + anti-undercut price floors
// ---------------------------------------------------------------------------

/** The binding shop-equivalents map (idea-02 §5 / V2/FIX-A spirit): every
 * park food must cost ≥ each of its closest normal-shop equivalents. */
const SHOP_EQUIVALENTS = Object.freeze({
  cottonCandy: ['lollypop', 'candy-bar'],
  softServe: ['ice-cream', 'sundae'],
  waffle: ['pancakes'],
});

test('V6/E3 park foods: exactly 3 rows, park-flagged, junk-classified, unique ids', () => {
  assert.equal(V6_PARK_FOODS.length, 3);
  assert.deepEqual(
    V6_PARK_FOODS.map((f) => f.id),
    ['cottonCandy', 'softServe', 'waffle']
  );
  assert.equal(new Set(FOODS.map((f) => f.id)).size, FOODS.length, 'no id collisions');
  for (const food of V6_PARK_FOODS) {
    assert.equal(food.park, true, `${food.id} carries park: true`);
    assert.equal(getFood(food.id), food, `${food.id} resolves via getFood`);
    assert.equal(typeof food.price, 'number');
    assert.equal(food.nameKey, `food.${food.id}`, `${food.id} nameKey pattern`);
    for (const stat of ['hunger', 'fun', 'energy', 'hygiene']) {
      assert.equal(typeof food.deltas[stat], 'number', `${food.id} deltas.${stat}`);
    }
  }
  // junk classification: cotton candy IS junk; one lighter non-junk option
  assert.equal(getFood('cottonCandy').junk, true, 'Zuckerwatte is junk');
  assert.equal(getFood('softServe').junk, true, 'Softeis is junk');
  assert.equal(getFood('waffle').junk, false, 'the waffle stays the lighter option');
});

test('V6/E3 park foods: priced ≥ every shop equivalent (anti-undercut)', () => {
  for (const [parkId, equivalents] of Object.entries(SHOP_EQUIVALENTS)) {
    const park = getFood(parkId);
    assert.ok(park?.park, `${parkId} is a park food`);
    assert.ok(equivalents.length > 0, `${parkId} has pinned equivalents`);
    for (const shopId of equivalents) {
      const shop = getFood(shopId);
      assert.ok(shop, `equivalent '${shopId}' exists`);
      assert.notEqual(shop.park, true, `equivalent '${shopId}' is a normal shop food`);
      assert.ok(
        park.price >= shop.price,
        `${parkId} (${park.price}c) must not undercut ${shopId} (${shop.price}c)`
      );
    }
  }
});

test('V6/E3 shop filter contract: park foods hidden, every other food untouched', () => {
  // the exact predicate shopScreen.js renderFood applies before its filters
  const shopVisible = FOODS.filter((f) => f.park !== true);
  for (const food of V6_PARK_FOODS) {
    assert.ok(!shopVisible.some((f) => f.id === food.id), `${food.id} hidden from the shop`);
  }
  assert.equal(shopVisible.length, FOODS.length - V6_PARK_FOODS.length,
    'only park rows are filtered');
});

test('V6/E3 park foods buy through economy.buyFood and feed like shop food', () => {
  for (const food of V6_PARK_FOODS) {
    const store = createStore(defaultState());
    store.set('coins', 100);
    assert.deepEqual(buyFood(store, food.id), { ok: true, total: food.price }, `${food.id} buys`);
    assert.equal(store.get('coins'), 100 - food.price, `${food.id} spends the catalog price`);
    assert.equal(invCount(store.get('inventory'), food.id), 1, `${food.id} lands in inventory`);

    const before = { hunger: 20, fun: 30, energy: 40, hygiene: 50 };
    const result = feedGooby({
      stats: before,
      inventory: store.get('inventory'),
      xp: 0,
      level: 1,
      health: 'healthy',
    }, food.id);
    assert.equal(result.ok, true, `${food.id} feeds through the normal care path`);
    assert.deepEqual(result.stats, {
      hunger: before.hunger + food.deltas.hunger,
      fun: before.fun + food.deltas.fun,
      energy: before.energy + food.deltas.energy,
      hygiene: before.hygiene + food.deltas.hygiene,
    }, `${food.id} exact applied deltas`);
    assert.equal(invCount(result.inventory, food.id), 0, `${food.id} consumed`);
  }
});

// ---------------------------------------------------------------------------
// Stall table + icon fallbacks + asset ground truth
// ---------------------------------------------------------------------------

test('V6/E3 stall table: 3 stalls, one park food each, sign/pitch keys resolve EN+DE', () => {
  assert.equal(PARK_STALLS.length, 3);
  assert.equal(new Set(PARK_STALLS.map((s) => s.id)).size, 3, 'stall ids unique');
  const stallFoods = PARK_STALLS.map((s) => s.foodId).sort();
  assert.deepEqual(stallFoods, V6_PARK_FOODS.map((f) => f.id).sort(),
    'stalls cover exactly the park foods');
  for (const stall of PARK_STALLS) {
    assert.equal(stall.signKey, `park.stall.${stall.id}.name`);
    for (const dict of [PARK_EN, PARK_DE]) {
      assert.ok(dict[stall.signKey], `${stall.signKey} present`);
      assert.ok(dict[`park.stall.${stall.id}.pitch`], `park.stall.${stall.id}.pitch present`);
      assert.ok(dict[`food.${stall.foodId}`], `food.${stall.foodId} present`);
    }
    assert.match(stall.tint, /^#[0-9A-Fa-f]{6}$/, `${stall.id} tint is a hex color`);
  }
});

test('V6/E3 icon fallbacks: every park food renders an authored glyph today', () => {
  const authored = new Set(foodIconIds());
  for (const food of V6_PARK_FOODS) {
    const fallback = PARK_FOOD_ICON_FALLBACK[food.id];
    assert.ok(
      authored.has(food.id) || authored.has(fallback),
      `${food.id}: neither an authored glyph nor a valid fallback ('${fallback}')`
    );
    const svg = parkFoodIcon(food.id, 30);
    assert.ok(svg.startsWith('<svg '), `${food.id} resolves to SVG markup`);
    assert.match(svg, /width="30" height="30"/, 'consumer-sized');
  }
});

test('V6/E3 asset ground truth: every dressing GLB key resolves to a committed file', async () => {
  const assets = await import('../src/core/assets.js');
  for (const key of PARK_DRESSING_ASSET_KEYS) {
    const url = assets.getModelUrl(key); // '/assets/<root>/<slug>/<name>.<ext>'
    const file = path.join(ROOT, 'public', ...url.replace(/^\//, '').split('/'));
    assert.ok(fs.existsSync(file), `dressing key '${key}' unresolved (${file})`);
  }
});

// ---------------------------------------------------------------------------
// Pure grounding + bunting helpers
// ---------------------------------------------------------------------------

test('V6/E3 groundOffset: snaps a scaled bbox min face exactly onto the ground', () => {
  assert.equal(groundOffset(-0.25), 0.25, 'sunken model is lifted');
  assert.equal(groundOffset(0.1), -0.1, 'floating model is lowered');
  assert.equal(groundOffset(0), 0, 'already grounded → no shift');
  assert.equal(groundOffset(-0.5, 2), 2.5, 'custom ground plane (counter tops)');
  // grounding invariant: min + offset === ground, for any measurement
  for (const minY of [-1.234, -0.001, 0, 0.42, 3.7]) {
    for (const ground of [0, 0.55, 2]) {
      assert.ok(Math.abs(minY + groundOffset(minY, ground) - ground) < 1e-12);
    }
  }
});

test('V6/E3 counterPlaneZ: measured wall face + exactly 2 cm anti-z-fight clearance', () => {
  assert.equal(PARK_DRESSING.COUNTER_CLEARANCE_M, 0.02, 'the binding +2 cm number');
  assert.equal(counterPlaneZ(1.0), 1.02);
  assert.equal(counterPlaneZ(0.37), 0.39);
  assert.equal(counterPlaneZ(1.0, 0.05), 1.05, 'clearance is explicit, not baked in');
  assert.ok(counterPlaneZ(0.5) > 0.5, 'always OUTSIDE the wall face');
});

test('V6/E3 buntingPoints: exact endpoints, apex sag at the middle, symmetric dip', () => {
  const a = { x: -2, y: 3, z: 0.5 };
  const b = { x: 2, y: 3.4, z: 0.5 };
  const pts = buntingPoints(a, b, 16, 0.32);
  assert.equal(pts.length, 17);
  assert.deepEqual(pts[0], a, 'starts exactly at anchor a');
  assert.deepEqual(pts[16], { x: 2, y: 3.4, z: 0.5 }, 'ends exactly at anchor b');
  // midpoint dips by exactly `sag` below the straight-line lerp
  const mid = pts[8];
  assert.ok(Math.abs(mid.y - ((3 + 3.4) / 2 - 0.32)) < 1e-12, 'apex sag = sag param');
  // every interior point hangs BELOW the straight line, symmetric dip
  for (let i = 1; i < 16; i++) {
    const s = i / 16;
    const lineY = a.y + (b.y - a.y) * s;
    assert.ok(pts[i].y < lineY, `interior point ${i} sags below the line`);
    const j = 16 - i;
    const dipI = lineY - pts[i].y;
    const dipJ = (a.y + (b.y - a.y) * (j / 16)) - pts[j].y;
    assert.ok(Math.abs(dipI - dipJ) < 1e-12, 'dip is symmetric');
  }
});

test('V6/E3 buntingSpots: interior-only, evenly spaced, on the sag curve', () => {
  const a = { x: 0, y: 2, z: 0 };
  const b = { x: 4, y: 2, z: 0 };
  const spots = buntingSpots(a, b, 7, 0.3);
  assert.equal(spots.length, 7);
  for (const p of spots) {
    assert.ok(p.x > 0 && p.x < 4, 'never on the anchors');
    assert.ok(p.y < 2, 'hangs below the anchor line');
  }
  // even spacing along x
  for (let i = 1; i < spots.length; i++) {
    assert.ok(Math.abs((spots[i].x - spots[i - 1].x) - 0.5) < 1e-12);
  }
});

// ---------------------------------------------------------------------------
// Band-swap bookkeeping model (the setBand contract as data)
// ---------------------------------------------------------------------------

test('V6/E3 bandVisual: lights on for dusk + night only', () => {
  assert.deepEqual(bandVisual('day'), { night: false });
  assert.deepEqual(bandVisual('dawn'), { night: false });
  assert.deepEqual(bandVisual('dusk'), { night: true });
  assert.deepEqual(bandVisual('night'), { night: true });
  assert.deepEqual(bandVisual('junk'), { night: false }, 'unknown band fails dark');
});

test('V6/E3 swapPlan: swap once per band change, night layer ≤ 2 added draw calls', () => {
  assert.ok(NIGHT_LAYER_DRAW_CALLS <= 2, 'the PLAN6 E3 budget pin');
  const BANDS = ['day', 'dawn', 'dusk', 'night'];

  // same band → strict no-op (materials swap ONCE per band change)
  for (const band of BANDS) {
    assert.deepEqual(swapPlan(band, band),
      { changed: false, nightToggled: false, nightCallsDelta: 0 });
  }
  // lights-on transitions add exactly the night layer, never more
  assert.deepEqual(swapPlan('day', 'night'),
    { changed: true, nightToggled: true, nightCallsDelta: NIGHT_LAYER_DRAW_CALLS });
  assert.deepEqual(swapPlan('dawn', 'dusk'),
    { changed: true, nightToggled: true, nightCallsDelta: NIGHT_LAYER_DRAW_CALLS });
  // lights-off transitions release the same calls
  assert.deepEqual(swapPlan('night', 'day'),
    { changed: true, nightToggled: true, nightCallsDelta: -NIGHT_LAYER_DRAW_CALLS });
  // band changes WITHIN a night state re-tint but add zero calls
  assert.deepEqual(swapPlan('day', 'dawn'),
    { changed: true, nightToggled: false, nightCallsDelta: 0 });
  assert.deepEqual(swapPlan('dusk', 'night'),
    { changed: true, nightToggled: false, nightCallsDelta: 0 });
  // exhaustive: |delta| never exceeds the budget
  for (const from of BANDS) {
    for (const to of BANDS) {
      const plan = swapPlan(from, to);
      assert.ok(Math.abs(plan.nightCallsDelta) <= NIGHT_LAYER_DRAW_CALLS,
        `${from}→${to} stays within the ≤${NIGHT_LAYER_DRAW_CALLS}-call budget`);
      assert.equal(plan.nightToggled,
        bandVisual(from).night !== bandVisual(to).night && from !== to);
    }
  }
});

// ---------------------------------------------------------------------------
// v6-park.js strings: EN/DE parity incl. E2's coaster caption block
// ---------------------------------------------------------------------------

test('V6/E3 v6-park strings: EN and DE carry identical, non-empty key sets', () => {
  const enKeys = Object.keys(PARK_EN).sort();
  const deKeys = Object.keys(PARK_DE).sort();
  assert.deepEqual(enKeys, deKeys, 'EN/DE key parity (incl. any E2 caption block)');
  assert.ok(enKeys.length > 0);
  for (const key of enKeys) {
    assert.ok(typeof PARK_EN[key] === 'string' && PARK_EN[key].length > 0, `EN '${key}' non-empty`);
    assert.ok(typeof PARK_DE[key] === 'string' && PARK_DE[key].length > 0, `DE '${key}' non-empty`);
  }
  // the sheet-level keys the stall panel + signage depend on
  for (const key of ['park.alley.title', 'park.alley.hint']) {
    assert.ok(PARK_EN[key] && PARK_DE[key], `${key} present in both`);
  }
  // every park food name follows the food.<id> resolution pattern
  for (const food of V6_PARK_FOODS) {
    assert.ok(PARK_EN[food.nameKey] && PARK_DE[food.nameKey], `${food.nameKey} in both dicts`);
  }
  // E2's delivered caption block (E2-strings-for-E3.txt) stays present verbatim
  const e2Keys = ['name', 'board', 'lift', 'drop', 'loop', 'photo', 'hills',
    'brake', 'done', 'handsUpHint', 'photoSaved'].map((k) => `park.coaster.${k}`);
  for (const key of e2Keys) {
    assert.ok(PARK_EN[key] && PARK_DE[key], `E2 caption ${key} present in both`);
  }
});
