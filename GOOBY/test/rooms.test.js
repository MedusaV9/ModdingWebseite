// Room-definition integrity (PLAN.md §G G4, PLAN2 §C2/§C8.2/§C8.3): the
// rooms/*.js tables are PURE data (no three.js/DOM imports) so this suite
// validates them headlessly — 5 rooms per §C2 (V2/G19: + the outdoor garden),
// every required anchor present, decor slot ids matching the §C5.2/§C8.3
// furniture catalogs, every default furniture asset present in the committed
// Kenney manifest, and the §C8.2 painter id sets complete (WALLPAPER_IDS /
// FLOOR_IDS import three.js transitively but stay importable under node).

import test from 'node:test';
import assert from 'node:assert/strict';
import { ROOMS } from '../src/data/constants.js';
import { PACKS, modelEntry } from '../scripts/kenney-manifest.mjs';
import { MODEL_PACKS as ITCH_MODEL_PACKS } from '../scripts/fetch-itch.mjs';
// V6/E4: KayKit Furniture Bits dressing stock (second asset root, §B6)
import { KAYKIT_PACKS, kaykitEntry } from '../scripts/kaykit-manifest.mjs';
import { STICKERS } from '../src/data/stickers.js';
import { ROOM as KITCHEN } from '../src/home/rooms/kitchen.js';
import { ROOM as LIVING } from '../src/home/rooms/living.js';
import { ROOM as BATHROOM } from '../src/home/rooms/bathroom.js';
import { ROOM as BEDROOM } from '../src/home/rooms/bedroom.js';
// V2/G19: 5th outdoor room (§C2.1) + the painter id exports (§C8.2)
import { ROOM as GARDEN, GARDEN_SIZE } from '../src/home/rooms/garden.js';
import { NAV_ORDER, WALLPAPER_IDS, FLOOR_IDS } from '../src/home/roomManager.js';

const DEFS = [KITCHEN, LIVING, BATHROOM, BEDROOM, GARDEN];
const byId = Object.fromEntries(DEFS.map((d) => [d.id, d]));

/** furniture-kit whitelist from the committed manifest (§D1). */
const FURNITURE_KIT = new Set(
  PACKS.find((p) => p.slug === 'furniture-kit').files.map((e) => modelEntry(e).key)
);

/**
 * V2/G19: every committed model key, pack-qualified ('nature-kit/tree_default')
 * — garden entries use multi-pack keys (§C2.1); bare names stay furniture-kit
 * (roomManager.resolveAssetKey).
 */
const ALL_PACK_KEYS = new Set(
  PACKS.filter((p) => p.modelDir).flatMap((p) =>
    p.files.map((e) => `${p.slug}/${modelEntry(e).key}`)
  )
);

/** V2/G19: does a room-table item name resolve to a committed GLB? */
const itemExists = (item) =>
  item.includes('/') ? ALL_PACK_KEYS.has(item) : FURNITURE_KIT.has(item);

/**
 * V2/G19: composite slot ids (no GLB of their own — rendered via a `pieces`
 * table on the furniture entry, e.g. the garden's wildflower cluster).
 */
const COMPOSITE_ITEMS = new Set(['wildflowers']);

/** §C5.2 decor slots per room + §C8.3 garden slots (binding catalog ids). */
const EXPECTED_SLOTS = {
  kitchen: ['tableSet', 'fridge', 'appliance', 'wallShelf', 'bar'],
  living: ['sofa', 'tv', 'rug', 'plant', 'lamp', 'bookcase', 'wallArt', 'ceilingFan', 'sideboard'],
  bathroom: ['tub', 'rug', 'plant', 'shelf', 'washer'],
  bedroom: ['bed', 'nightstand', 'rug', 'plushie', 'sideTable', 'floorClutter'],
  // V2/G19 (§C8.3): 6 garden decor slots
  garden: ['gardenBench', 'gardenGnome', 'birdbath', 'flowerBed', 'gardenPath', 'gardenTree'],
};

/** Required getAnchor names (§G G4 + V2/G19 §C2.1) and their owning rooms. */
const REQUIRED_ANCHORS = {
  bed: 'bedroom',
  bathtub: 'bathroom',
  fridge: 'kitchen',
  sofa: 'living',
  tv: 'living',
  frontDoor: 'living',
  toilet: 'bathroom',
  lampSwitch: 'bedroom',
  wardrobe: 'bedroom',
  ballSpawn: 'living',
  // V2/G19 (§C2.1): garden plots + tools
  plot0: 'garden',
  plot1: 'garden',
  plot2: 'garden',
  plot3: 'garden',
  plot4: 'garden',
  plot5: 'garden',
  compost: 'garden',
  wateringCan: 'garden',
  fertilizer: 'garden',
  // V6/E4 (PLAN6 Wave E/F contract): fence-post perch for Wave F's transient
  // bird visitor — the anchor ships with the room rebuild, the moving bird
  // is ambient/Wave F's.
  gardenFenceBird: 'garden',
};

/** Fixed interactables that must emit tap events (§C2/§G G4 + V2/G19). */
const REQUIRED_INTERACTS = {
  fridge: 'kitchen',
  tv: 'living',
  frontDoor: 'living',
  bathtub: 'bathroom',
  toilet: 'bathroom',
  bed: 'bedroom',
  lampSwitch: 'bedroom',
  wardrobe: 'bedroom',
  // V2/G19 (§C2.2): plot taps, compost sell sheet, tool hints/sheets
  plot0: 'garden',
  plot1: 'garden',
  plot2: 'garden',
  plot3: 'garden',
  plot4: 'garden',
  plot5: 'garden',
  compost: 'garden',
  wateringCan: 'garden',
  fertilizer: 'garden',
};

/** Every anchor name a room def provides (slot ids auto-register anchors). */
function anchorNames(def) {
  const names = new Set(Object.keys(def.anchors));
  for (const entry of def.furniture) {
    if (entry.anchor) names.add(entry.anchor);
    if (entry.slot) names.add(entry.slot);
  }
  return names;
}

/**
 * V2/G19: room-shell half extents — the garden ground is 5×4 m (§C2.1),
 * indoor shells stay 4×3 m (SHELL in roomManager.js, kept in sync by hand).
 */
function halfExtents(def) {
  if (def.outdoor) return { w: GARDEN_SIZE.WIDTH / 2, d: GARDEN_SIZE.DEPTH / 2 };
  return { w: 2.0, d: 1.5 };
}

test('there are exactly 5 rooms in §C2/§B3 order (garden last)', () => {
  assert.deepEqual(
    DEFS.map((d) => d.id),
    ['kitchen', 'living', 'bathroom', 'bedroom', 'garden']
  );
  // v1 constants stay untouched (§E0.1-2) — the 5-room order is NAV_ORDER
  assert.deepEqual(DEFS.slice(0, 4).map((d) => d.id), [...ROOMS.ORDER]);
  assert.deepEqual([...NAV_ORDER], [...ROOMS.ORDER, 'garden']);
});

test('the garden is the only outdoor room (§B3)', () => {
  assert.equal(GARDEN.outdoor, true);
  for (const def of DEFS) {
    if (def.id !== 'garden') assert.ok(!def.outdoor, `${def.id}: unexpectedly outdoor`);
  }
});

test('room defs are pure data (arrays/plain objects, frozen)', () => {
  for (const def of DEFS) {
    assert.ok(Object.isFrozen(def), `${def.id}: def not frozen`);
    assert.ok(Array.isArray(def.furniture), `${def.id}: furniture not an array`);
    assert.equal(typeof def.slots, 'object');
    assert.equal(typeof def.anchors, 'object');
  }
});

test('decor slot ids match the §C5.2/§C8.3 furniture catalogs', () => {
  for (const [roomId, expected] of Object.entries(EXPECTED_SLOTS)) {
    assert.deepEqual(
      Object.keys(byId[roomId].slots).sort(),
      [...expected].sort(),
      `${roomId}: slot ids diverge from §C5.2/§C8.3`
    );
  }
});

test('V2/FIX-C: reward-only slots never collide with the frozen room-def slots', async () => {
  // the §C6 set-reward decos live in CATALOG-ONLY slots (decor.js positions
  // them via REWARD_SLOT_SPOTS) — a room def gaining a same-named slot would
  // silently shadow the reward placement, so guard the namespace here
  const { rewardSlots } = await import('../src/data/furniture.js');
  for (const def of DEFS) {
    for (const slotId of rewardSlots(def.id)) {
      assert.ok(
        !(slotId in def.slots),
        `${def.id}.${slotId}: reward slot id collides with a room-def slot`
      );
    }
  }
});

test('every slot default is a member of its variant list', () => {
  for (const def of DEFS) {
    for (const [slotId, slot] of Object.entries(def.slots)) {
      assert.ok(Array.isArray(slot.items) && slot.items.length > 0, `${def.id}.${slotId}: empty variants`);
      if (slot.default != null) {
        assert.ok(
          slot.items.includes(slot.default),
          `${def.id}.${slotId}: default '${slot.default}' not in variants`
        );
      }
    }
  }
});

test('every GLB slot variant + default exists in the Kenney manifest', () => {
  for (const def of DEFS) {
    for (const [slotId, slot] of Object.entries(def.slots)) {
      for (const item of slot.items) {
        if (item.startsWith('proc:')) continue; // procedural (§C5.2 wall art, gnomes…)
        if (COMPOSITE_ITEMS.has(item)) continue; // pieces-table composites (V2/G19)
        assert.ok(itemExists(item), `${def.id}.${slotId}: '${item}' missing from the manifest`);
      }
    }
  }
});

test('composite slot items provide a pieces table of committed GLBs (V2/G19)', () => {
  for (const def of DEFS) {
    for (const [slotId, slot] of Object.entries(def.slots)) {
      for (const item of slot.items) {
        if (!COMPOSITE_ITEMS.has(item)) continue;
        const entry = def.furniture.find((f) => f.slot === slotId && f.item === item);
        assert.ok(entry?.pieces?.length, `${def.id}.${slotId}: composite '${item}' has no pieces table`);
      }
    }
  }
});

test('every placed furniture item (incl. set pieces + variant sets) exists in the manifest', () => {
  for (const def of DEFS) {
    for (const entry of def.furniture) {
      const items = [];
      if (entry.pieces) items.push(...entry.pieces.map((p) => p.item));
      else if (entry.item) items.push(entry.item);
      if (entry.piecesByItem) {
        for (const set of Object.values(entry.piecesByItem)) items.push(...set.map((p) => p.item));
      }
      for (const item of items) {
        assert.ok(itemExists(item), `${def.id}: placed item '${item}' missing from the manifest`);
      }
    }
  }
});

test('V3/G46 static room dressing uses committed real assets within the per-room cap', () => {
  const expected = {
    kitchen: ['kitchenCoffeeMachine'],
    living: ['lampSquareCeiling'],
    bathroom: ['lampSquareCeiling'],
    bedroom: ['plantSmall1'],
    garden: ['nature-kit/fence_gate', 'nature-kit/bench'],
  };
  for (const def of DEFS) {
    const dressing = def.furniture.filter((entry) => entry.dressing === 'v3-real-asset');
    assert.ok(dressing.length <= 3, `${def.id}: more than 3 static dressing entries`);
    assert.deepEqual(dressing.map((entry) => entry.item), expected[def.id], `${def.id}: dressing`);
    for (const entry of dressing) {
      assert.ok(itemExists(entry.item), `${def.id}: dressing '${entry.item}' missing from manifest`);
    }
  }
});

test('V3/G46 garden uses real additions but keeps the compost identity item procedural', () => {
  const items = new Set(
    GARDEN.furniture.flatMap((entry) => [
      ...(entry.item ? [entry.item] : []),
      ...(entry.pieces?.map((piece) => piece.item) ?? []),
    ])
  );
  for (const key of [
    'nature-kit/bench',
    'nature-kit/fence_gate',
    'nature-kit/flower_purpleA',
    'nature-kit/flower_redA',
    'nature-kit/stump_round',
  ]) {
    assert.ok(items.has(key), `garden missing ${key}`);
  }
  const compost = GARDEN.furniture.find((entry) => entry.interact === 'compost');
  assert.equal(compost?.proc, 'compostBin');
  assert.equal(compost?.item, undefined);
});

test('V6/E4 room dressing is complete, asset-backed, and inside the draw-call budget', () => {
  const expected = {
    // V5/ASSETS: kitchenware/bathware Tiny Treats clusters; V6/E4: baked-goods
    // breakfast (own batch — the pack embeds its own atlas copy)
    kitchen: ['wallTrim', 'bakeryCorner', 'hangingUtensils', 'kitchenware', 'breakfastSet'],
    // V6/E4: KayKit reading nook + Tiny Treats monstera (the Aline plant
    // moved to the bedroom); V6/FIX4 (P1-7): + lit bulbs (ceiling fixture
    // anchors the night glow, standing lamp reads lit on wide viewports)
    living: ['alineBookshelf', 'pictureFirstNom', 'pictureBallBuddy', 'readingNook', 'livingPlants', 'ceilingLampGlow', 'readingLampGlow'],
    bathroom: ['wallTrim', 'towelRail', 'alineCactus', 'bathware'],
    // V6/E4: KayKit cozy corner + relocated Aline plant + sansevieria;
    // V6/FIX4 (P1-8): + folded blanket on the bed (replaces the bear mask)
    bedroom: ['alineRug', 'fairyLights', 'pictureSleepyhead', 'cozyCorner', 'alinePlant', 'bedroomPlants', 'foldedBlanket'],
    // V6/E4: the garden ships a dressing table now — Tiny Treats park pieces
    // (pretty-park has its OWN atlas revision ⇒ separate batch from the
    // pleasant-picnic baskets) + the checkered-blanket painter
    garden: ['parkDressing', 'picnicCorner', 'picnicBlanket'],
  };
  // V6/E4 (PLAN6 Wave E budget): per-room dressing draw calls — colored merge
  // + one call per textured atlas batch + fairy dots + one per picture + one
  // per blanket quad. The plan's bar is ≤4 calls ADDED per room over the V5
  // baseline {kitchen 3, living 3, bathroom 2, bedroom 3, garden 0}.
  // V6/FIX4 (P1-7): living 5 → 6 — the readingLampGlow bulb opens the
  // emissive `fairy` batch in the living room (adds 3 vs baseline, ≤4 OK).
  const expectedCalls = { kitchen: 4, living: 6, bathroom: 2, bedroom: 5, garden: 3 };
  const baselineCalls = { kitchen: 3, living: 3, bathroom: 2, bedroom: 3, garden: 0 };
  const itchKeys = new Set(
    ITCH_MODEL_PACKS.flatMap((pack) => pack.files.map(({ key }) => `${pack.slug}/${key}`))
  );
  // V6/E4: KayKit Furniture Bits joins the dressing stock (second asset root)
  const kaykitKeys = new Set(
    KAYKIT_PACKS.flatMap((pack) => pack.files.map((entry) => `${pack.slug}/${kaykitEntry(entry, pack.ext).key}`))
  );
  const stickerIds = new Set(STICKERS.map((sticker) => sticker.id));

  for (const [roomId, ids] of Object.entries(expected)) {
    const dressing = byId[roomId].dressing;
    assert.ok(Object.isFrozen(dressing), `${roomId}: dressing table not frozen`);
    assert.deepEqual(dressing.map((entry) => entry.id), ids, `${roomId}: dressing recipe`);
    assert.equal(new Set(ids).size, ids.length, `${roomId}: duplicate dressing id`);

    for (const entry of dressing) {
      assert.ok(Object.isFrozen(entry), `${roomId}.${entry.id}: entry not frozen`);
      const pieces = entry.kind === 'assetCluster' ? entry.pieces : [entry];
      for (const piece of pieces) {
        if (piece.key) {
          assert.ok(
            itchKeys.has(piece.key) || kaykitKeys.has(piece.key),
            `${roomId}.${entry.id}: asset '${piece.key}' missing from the itch/kaykit manifests`
          );
        }
      }
      if (entry.kind === 'picture') {
        assert.ok(stickerIds.has(entry.art), `${roomId}.${entry.id}: unknown sticker '${entry.art}'`);
      }
    }

    const colored = dressing.some((entry) =>
      ['asset', 'wallTrim', 'hangingUtensils', 'towelRail', 'fairyLights', 'picture', 'foldedBlanket']
        .includes(entry.kind)
    ) ? 1 : 0;
    const textured = new Set(
      dressing.filter((entry) => entry.kind === 'assetCluster').map((entry) => entry.batch)
    ).size;
    const emissive = dressing.some(
      (entry) => entry.kind === 'fairyLights' || entry.kind === 'lampGlow'
    ) ? 1 : 0;
    const pictures = dressing.filter((entry) => entry.kind === 'picture').length;
    const blankets = dressing.filter((entry) => entry.kind === 'picnicBlanket').length;
    const calls = colored + textured + emissive + pictures + blankets;
    assert.equal(calls, expectedCalls[roomId], `${roomId}: dressing draw-call recipe changed`);
    assert.ok(
      calls - baselineCalls[roomId] <= 4,
      `${roomId}: dressing adds ${calls - baselineCalls[roomId]} calls — over the ≤4-added budget`
    );
  }
});

test('all required anchors are present in their owning rooms', () => {
  for (const def of DEFS) {
    assert.ok(anchorNames(def).has('goobyIdle'), `${def.id}: missing goobyIdle anchor`);
  }
  for (const [name, roomId] of Object.entries(REQUIRED_ANCHORS)) {
    assert.ok(anchorNames(byId[roomId]).has(name), `${roomId}: missing required anchor '${name}'`);
  }
});

test('every §C5.2/§C8.3 decor slot registers a per-room slot anchor', () => {
  for (const def of DEFS) {
    const names = anchorNames(def);
    for (const slotId of Object.keys(def.slots)) {
      assert.ok(names.has(slotId), `${def.id}: slot '${slotId}' has no anchor position`);
    }
  }
});

test('fixed interactables declare their tap events (§C2)', () => {
  for (const [name, roomId] of Object.entries(REQUIRED_INTERACTS)) {
    const found = byId[roomId].furniture.some((entry) => entry.interact === name);
    assert.ok(found, `${roomId}: no furniture entry emits 'tap:${name}'`);
  }
});

test('the six garden plots form the §C2.1 2×3 grid with tap hitboxes', () => {
  const plots = GARDEN.furniture.filter((e) => /^plot[0-5]$/.test(e.interact ?? ''));
  assert.equal(plots.length, 6, 'garden: expected exactly 6 plot entries');
  const rows = new Set(plots.map((e) => e.at[2]));
  const cols = new Set(plots.map((e) => e.at[0]));
  assert.equal(rows.size, 2, 'garden: plots must sit on 2 z-rows');
  assert.equal(cols.size, 3, 'garden: plots must sit on 3 x-columns');
  for (const entry of plots) {
    assert.equal(entry.item, 'nature-kit/crops_dirtSingle', `garden: ${entry.interact} wrong dirt model`);
    assert.ok(entry.hitSize, `garden: ${entry.interact} missing hitSize`);
    assert.equal(entry.anchor, entry.interact, `garden: ${entry.interact} anchor/interact mismatch`);
  }
});

test('V4/POLISH-I: garden plots keep the 0.85 m pitch (PLOT_RADIUS contract)', () => {
  // gardenInteractions.js resolves drag targets by nearest plot within
  // PLOT_RADIUS 0.42, tuned for the 0.85 m grid pitch — the room rebuild must
  // not drift the grid.
  const plots = GARDEN.furniture.filter((e) => /^plot[0-5]$/.test(e.interact ?? ''));
  const cols = [...new Set(plots.map((e) => e.at[0]))].sort((a, b) => a - b);
  const rows = [...new Set(plots.map((e) => e.at[2]))].sort((a, b) => a - b);
  for (let i = 1; i < cols.length; i += 1) {
    assert.ok(Math.abs(cols[i] - cols[i - 1] - 0.85) < 1e-9, 'garden: column pitch drifted from 0.85 m');
  }
  assert.ok(Math.abs(rows[1] - rows[0] - 0.85) < 1e-9, 'garden: row pitch drifted from 0.85 m');
});

test('V4/POLISH-I: every fixed interactable keeps a 3-component tap hitSize', () => {
  // the POLISH-I room rebuild repositions furniture — the care/garden flows in
  // interactions.js + gardenInteractions.js need every tap target to keep an
  // explicit raycast box.
  for (const [name, roomId] of Object.entries(REQUIRED_INTERACTS)) {
    const entry = byId[roomId].furniture.find((e) => e.interact === name);
    assert.equal(entry?.hitSize?.length, 3, `${roomId}.${name}: missing hitSize`);
  }
});

test('V4/POLISH-I: the living-room layered rugs stack without z-fighting', () => {
  const under = byId.living.furniture.find((e) => e.item === 'rugSquare' && !e.slot);
  const slotRug = byId.living.furniture.find((e) => e.slot === 'rug');
  assert.ok(under, 'living: base rug of the layered pair missing');
  assert.ok(under.noShadow, 'living: base rug must skip shadow casting');
  assert.ok(slotRug.at[1] >= 0.01, 'living: accent rug must be lifted above the base rug');
});

test('§C8.2 painter id sets are complete (10 wallpapers / 7 floors)', () => {
  assert.deepEqual(
    [...WALLPAPER_IDS].sort(),
    ['candy', 'cream', 'lavender', 'meadow', 'mint', 'ocean', 'peach', 'sky', 'stars', 'sunset'],
    'wallpaper ids diverge from §C5.2 + §C8.2'
  );
  assert.deepEqual(
    [...FLOOR_IDS].sort(),
    ['carpet', 'checker', 'marble', 'terracotta', 'tile', 'walnut', 'wood'],
    'floor ids diverge from §C5.2 + §C8.2'
  );
});

test('variant piece layouts (piecesByItem) keep pieces inside the shell', () => {
  // P2-6: per-variant offsets/scales exist to keep oversized variants (corner
  // sofa, drawer cabinet, square rug…) from sinking into walls or hanging off
  // the floor — sanity-check the layout tables stay inside the shell footprint.
  for (const def of DEFS) {
    const { w: HALF_W, d: HALF_D } = halfExtents(def);
    for (const entry of def.furniture) {
      const sets = [
        ...(entry.pieces ? [['pieces', entry.pieces]] : []),
        ...Object.entries(entry.piecesByItem ?? {}),
      ];
      for (const [variant, pieces] of sets) {
        for (const piece of pieces) {
          const x = entry.at[0] + piece.at[0];
          const z = entry.at[2] + piece.at[2];
          assert.ok(Math.abs(x) <= HALF_W + 0.01, `${def.id}.${variant}: piece '${piece.item}' x=${x} outside shell`);
          assert.ok(Math.abs(z) <= HALF_D + 0.01, `${def.id}.${variant}: piece '${piece.item}' z=${z} outside shell`);
          if (piece.scale != null) {
            assert.ok(Number.isFinite(piece.scale) && piece.scale > 0, `${def.id}.${variant}: piece '${piece.item}' bad scale`);
          }
        }
      }
    }
  }
});

test('furniture placements sit inside their room shell (§C2)', () => {
  // indoor shells are 4×3 m (SHELL in roomManager.js — kept in sync by hand
  // since that module imports three.js); the garden ground is 5×4 m (§C2.1).
  // The garden's back fence/hedge line may straddle the ground edge slightly
  // (outdoor composition), hence the small tolerance below.
  for (const def of DEFS) {
    const { w: HALF_W, d: HALF_D } = halfExtents(def);
    const tol = def.outdoor ? 0.15 : 0.01;
    for (const entry of def.furniture) {
      const [x, y, z] = entry.at;
      assert.ok(Math.abs(x) <= HALF_W + tol, `${def.id}: entry at x=${x} outside shell`);
      assert.ok(Math.abs(z) <= HALF_D + tol, `${def.id}: entry at z=${z} outside shell`);
      assert.ok(y >= 0 && y <= 3.2, `${def.id}: entry lift y=${y} outside shell`);
    }
    for (const [name, at] of Object.entries(def.anchors)) {
      assert.ok(
        Math.abs(at[0]) <= HALF_W + tol && Math.abs(at[2]) <= HALF_D + tol,
        `${def.id}: anchor '${name}' outside shell`
      );
    }
  }
});
