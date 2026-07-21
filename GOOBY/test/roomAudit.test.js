// V4/AC-3D: the machine-checkable 3D-placement guarantee (headless).
//
// The user-facing bar: no placed model in the 5 home rooms may clip into
// another, face the wrong way, stand tilted, float, sink, pierce a wall or
// hang outside its shell. Three layers lock it:
//   1. the ZERO-WARNING lock — auditRoom() must return [] for every room def
//      (any future placement regression fails right here);
//   2. synthetic detector proofs — deliberately broken layouts must produce
//      exactly the expected warning types (so an empty result means "checked
//      and clean", never "checker is blind");
//   3. the DRIFT lock — computePlacedBoxes' pure transform replay must agree
//      with the live scene-graph AABBs dumped into the fixture by
//      scripts/gen-asset-bounds.mjs (≤ 0.05 m per axis). If roomManager's
//      placement chain ever changes, this fails and the fixture/audit must be
//      regenerated together.
//
// The fixture (test/fixtures/asset-bounds.json) is generated — never
// hand-edit; re-run `node scripts/gen-asset-bounds.mjs` against the dev VM
// recipe (dev server :5174 + headless Chrome CDP) after asset/placement work.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { ROOM as KITCHEN } from '../src/home/rooms/kitchen.js';
import { ROOM as LIVING } from '../src/home/rooms/living.js';
import { ROOM as BATHROOM } from '../src/home/rooms/bathroom.js';
import { ROOM as BEDROOM } from '../src/home/rooms/bedroom.js';
import { ROOM as GARDEN } from '../src/home/rooms/garden.js';
import {
  auditRoom, auditAllRooms, computePlacedBoxes, resolveAssetKey,
  FURNITURE_SCALE, DEFAULT_TOLERANCES,
} from '../src/home/roomAudit.js';
import { AUDIT_RULES } from '../src/home/roomAudit.rules.js';

const DEFS = [KITCHEN, LIVING, BATHROOM, BEDROOM, GARDEN];

const FIXTURE = JSON.parse(readFileSync(
  fileURLToPath(new URL('./fixtures/asset-bounds.json', import.meta.url)), 'utf8'
));

// ---------------------------------------------------------------------------
// 1) the regression lock: all five rooms audit to ZERO warnings
// ---------------------------------------------------------------------------

for (const def of DEFS) {
  test(`V4/AC-3D zero-warning lock: '${def.id}' has no clip/facing/tilt/float/sunk/wall issues`, () => {
    const warnings = auditRoom(def, FIXTURE, AUDIT_RULES);
    assert.deepEqual(
      warnings.map((w) => `[${w.type}] ${w.msg}`), [],
      `${def.id}: the room layout regressed — fix the placement (or, for a `
      + 'deliberate composition, add a reviewed allowance in roomAudit.rules.js)'
    );
  });
}

test('V4/AC-3D: auditAllRooms reports a clean house', () => {
  assert.deepEqual(auditAllRooms(DEFS, FIXTURE, AUDIT_RULES), {});
});

// ---------------------------------------------------------------------------
// 2) synthetic detector proofs — a checker that cannot fail proves nothing
// ---------------------------------------------------------------------------

/** 1×1×1 m cube around the origin footprint (bottom at y −0), fwd +z. */
const CUBE = { min: [-0.5, 0, -0.5], max: [0.5, 1, 0.5], forward: [0, 0, 1] };
const SYN_BOUNDS = {
  meta: FIXTURE.meta,
  assets: {
    'syn/box': CUBE,
    'syn/sofa': { min: [-0.75, 0, -0.35], max: [0.75, 0.7, 0.35], forward: [0, 0, 1] },
    'syn/rug': { min: [-0.6, 0, -0.4], max: [0.6, 0.02, 0.4], forward: null },
  },
};
/** Bare synthetic room around the origin (indoor 4×3 shell). */
const synRoom = (furniture, dressing) => ({ id: 'synthetic', furniture, dressing });
// synthetic native boxes are already unit-scaled — bypass FURNITURE_SCALE
const SYN_OPTS = { furnitureScale: 1 };
const synAudit = (roomDef, rules = {}) =>
  auditRoom(roomDef, SYN_BOUNDS, rules, SYN_OPTS);

test('detector: two overlapping boxes → clip (and flush placement stays legal)', () => {
  const clipped = synAudit(synRoom([
    { item: 'syn/box', at: [0, 0, 0], rotY: 0 },
    { item: 'syn/box', at: [0.8, 0, 0], rotY: 0 }, // 0.2 m interpenetration
  ]));
  assert.equal(clipped.length, 1);
  assert.equal(clipped[0].type, 'clip');
  assert.ok(clipped[0].amount > 0.19 && clipped[0].amount < 0.21, `amount ${clipped[0].amount}`);

  const flush = synAudit(synRoom([
    { item: 'syn/box', at: [0, 0, 0], rotY: 0 },
    { item: 'syn/box', at: [1.0, 0, 0], rotY: 0 }, // exactly side by side
  ]));
  assert.deepEqual(flush, []);
});

test('detector: rug under furniture and deliberate y-stacks are whitelisted, not clips', () => {
  const warnings = synAudit(synRoom([
    { item: 'syn/rug', at: [0, 0, 0], rotY: 0 },
    { item: 'syn/box', at: [0, 0, 0], rotY: 0 }, // on the rug
    { item: 'syn/box', at: [0, 1.0, 0], rotY: 0 }, // stacked on the first box
  ]));
    assert.deepEqual(warnings, []);
});

// ---------------------------------------------------------------------------
// V4/FIX-3D hardening regressions — the garden tree∩compost class of bug
// (a LARGE overlap shipping unseen because its pair was whitelisted, plus
// coplanar-flat z-fighting hiding behind the blanket flat skip).
// ---------------------------------------------------------------------------

test('V4/FIX-3D regression: clipAllow is BOUNDED — a large allowed-pair overlap is still flagged', () => {
  // the exact bug class of the original garden layout: tree∩compost was on
  // the clipAllow list, so its 0.32 m canopy-through-bin clip never warned.
  const allowRules = { rooms: { synthetic: { clipAllow: [['syn/box', 'syn/sofa']] } } };
  // 0.5 m interpenetration — way past the 0.30 m clipAllowMax cap
  const deep = synAudit(synRoom([
    { item: 'syn/box', at: [0, 0, 0], rotY: 0 },
    { item: 'syn/sofa', at: [0.75, 0, 0], rotY: 0 },
  ]), allowRules);
  assert.equal(deep.length, 1, JSON.stringify(deep));
  assert.equal(deep[0].type, 'clip');
  assert.ok(/clipAllow cap/.test(deep[0].msg), deep[0].msg);
  // a shallow 0.2 m overlap stays forgiven by the same allowance
  const shallow = synAudit(synRoom([
    { item: 'syn/box', at: [0, 0, 0], rotY: 0 },
    { item: 'syn/sofa', at: [1.05, 0, 0], rotY: 0 },
  ]), allowRules);
  assert.deepEqual(shallow, []);
  // a pair may carry its OWN tighter cap as a third tuple element
  const tight = { rooms: { synthetic: { clipAllow: [['syn/box', 'syn/sofa', 0.1]] } } };
  const overTightCap = synAudit(synRoom([
    { item: 'syn/box', at: [0, 0, 0], rotY: 0 },
    { item: 'syn/sofa', at: [1.05, 0, 0], rotY: 0 }, // same 0.2 m overlap
  ]), tight);
  assert.equal(overTightCap.length, 1, JSON.stringify(overTightCap));
  assert.ok(/0.10 m clipAllow cap/.test(overTightCap[0].msg), overTightCap[0].msg);
});

test('V4/FIX-3D regression: the PRE-FIX garden layout is flagged even with the old allowance', () => {
  // rebuild the shipped-buggy garden: tree at x 1.9 + compost at 1.5/rotY −15
  // (the V4/FIX-3D commit moved both), and put the OLD unlimited-looking
  // tree∩compost allowance back — the bounded cap must flag it anyway.
  const preFurniture = GARDEN.furniture.map((e) => {
    if (e.slot === 'gardenTree') return { ...e, at: [1.9, 0, -1.45] };
    if (e.proc === 'compostBin') return { ...e, at: [1.5, 0, -1.15], rotY: -15 };
    return e;
  });
  const preGarden = { ...GARDEN, furniture: preFurniture };
  const oldRules = {
    rooms: {
      ...AUDIT_RULES.rooms,
      garden: {
        ...AUDIT_RULES.rooms.garden,
        clipAllow: [['nature-kit/tree_default', 'proc:compostBin']],
      },
    },
  };
  const warnings = auditRoom(preGarden, FIXTURE, oldRules);
  const clip = warnings.filter((w) => w.type === 'clip'
    && /tree_default/.test(w.msg) && /compostBin/.test(w.msg));
  assert.equal(clip.length, 1, JSON.stringify(warnings));
  assert.ok(clip[0].amount > 0.3, `expected the ~0.32 m overlap, got ${clip[0].amount}`);
  // and the SHIPPED layout is genuinely clean under the same hardened rules
  assert.deepEqual(auditRoom(GARDEN, FIXTURE, AUDIT_RULES), []);
});

test('V4/FIX-3D regression: coplanar flats z-fight; deliberately layered flats stay legal', () => {
  // two rugs at the SAME height — top surfaces coincide → shimmering
  const coplanar = synAudit(synRoom([
    { item: 'syn/rug', at: [0, 0, 0], rotY: 0 },
    { item: 'syn/rug', at: [0.3, 0, 0], rotY: 0 },
  ]));
  assert.equal(coplanar.length, 1, JSON.stringify(coplanar));
  assert.equal(coplanar[0].type, 'clip');
  assert.ok(/z-fights/.test(coplanar[0].msg), coplanar[0].msg);
  // layered composition: tops ≥ flatFightGap apart reads as a deliberate stack
  const layered = synAudit(synRoom([
    { item: 'syn/rug', at: [0, 0, 0], rotY: 0 },
    { item: 'syn/rug', at: [0.3, 0.01, 0], rotY: 0 },
  ]));
  assert.deepEqual(layered, []);
});

test('detector: sofa turned to face the back wall → facing (both cone and wall-back)', () => {
  const rules = {
    rooms: {
      synthetic: { facing: { 'syn/sofa': { mode: 'camera', wallBacked: true } } },
    },
  };
  // correctly placed: back on the back wall, facing the camera
  const good = synAudit(synRoom([{ item: 'syn/sofa', at: [0, 0, -1.1], rotY: 0 }]), rules);
  assert.deepEqual(good, []);
  // spun 180°: faces the wall AND its back gapes toward the room
  const spun = synAudit(synRoom([{ item: 'syn/sofa', at: [0, 0, -1.1], rotY: 180 }]), rules);
  assert.ok(spun.some((w) => w.type === 'facing' && /faces 180°/.test(w.msg)), JSON.stringify(spun));
  // facing fine but stranded mid-room: the wall-backed check fires
  const stranded = synAudit(synRoom([{ item: 'syn/sofa', at: [0, 0, 0.5], rotY: 0 }]), rules);
  assert.ok(
    stranded.some((w) => w.type === 'facing' && /should back onto/.test(w.msg)),
    JSON.stringify(stranded)
  );
});

test('detector: box shoved past z −1.5 → wall-penetration; past the side edge → out-of-shell', () => {
  const back = synAudit(synRoom([{ item: 'syn/box', at: [0, 0, -1.3], rotY: 0 }]));
  assert.equal(back.length, 1);
  assert.equal(back[0].type, 'wall-penetration');
  assert.ok(back[0].amount > 0.29 && back[0].amount < 0.31, `amount ${back[0].amount}`);

  const side = synAudit(synRoom([{ item: 'syn/box', at: [1.9, 0, 1.0], rotY: 0 }]));
  assert.equal(side.length, 1);
  assert.equal(side[0].type, 'out-of-shell');
});

test('detector: unsupported lift → float; below the floor → sunk; supported lift is fine', () => {
  const floating = synAudit(synRoom([{ item: 'syn/box', at: [0, 0.5, 0], rotY: 0 }]));
  assert.equal(floating.length, 1);
  assert.equal(floating[0].type, 'float');

  const sunk = synAudit(synRoom([{ item: 'syn/box', at: [0, -0.2, 0], rotY: 0 }]));
  assert.equal(sunk.length, 1);
  assert.equal(sunk[0].type, 'sunk');

  const shelfed = synAudit(synRoom([
    { item: 'syn/box', at: [0, 0, 0], rotY: 0 },
    { item: 'syn/box', at: [0, 1.02, 0], rotY: 0 }, // resting on the lower box
  ]));
  assert.deepEqual(shelfed, []);
});

test('detector: non-whitelisted dressing rotX/rotZ → tilt (whitelist silences it)', () => {
  const room = synRoom([], [
    { id: 'leaner', kind: 'asset', key: 'syn/box', at: [0, 0, 0], rotX: -90 },
  ]);
  const tilted = synAudit(room);
  assert.ok(tilted.some((w) => w.type === 'tilt'), JSON.stringify(tilted));
  const allowed = synAudit(room, { rooms: { synthetic: { tiltAllow: ['syn/box'] } } });
  assert.ok(!allowed.some((w) => w.type === 'tilt'), JSON.stringify(allowed));
});

test('detector: rotY math matches three.js handedness (rotY 90 turns +z forward to +x)', () => {
  const rules = {
    rooms: { synthetic: { facing: { 'syn/box': { mode: 'vector', dir: [1, 0], maxDeg: 5 } } } },
  };
  assert.deepEqual(synAudit(synRoom([{ item: 'syn/box', at: [0, 0, 0], rotY: 90 }]), rules), []);
  const wrong = synAudit(synRoom([{ item: 'syn/box', at: [0, 0, 0], rotY: -90 }]), rules);
  assert.ok(wrong.some((w) => w.type === 'facing'), JSON.stringify(wrong));
});

// ---------------------------------------------------------------------------
// 3) fixture completeness + the pure-vs-live drift lock
// ---------------------------------------------------------------------------

test('fixture completeness: every default-placed key in every room def is measured', () => {
  const missing = [];
  for (const def of DEFS) {
    for (const entry of def.furniture) {
      if (entry.slot && !entry.item && !entry.pieces && !entry.proc) continue;
      const keys = entry.proc
        ? [`proc:${entry.proc}`]
        : (entry.pieces ?? [entry]).map((piece) => resolveAssetKey(piece.item));
      for (const key of keys) {
        if (!FIXTURE.assets[key]) missing.push(`${def.id}: ${key}`);
      }
    }
    for (const entry of def.dressing ?? []) {
      if (entry.kind !== 'asset' && entry.kind !== 'assetCluster') continue;
      const pieces = entry.kind === 'assetCluster' ? entry.pieces : [entry];
      for (const piece of pieces) {
        if (!FIXTURE.assets[piece.key]) missing.push(`${def.id}: ${piece.key}`);
      }
    }
  }
  assert.deepEqual(missing, [], 're-run scripts/gen-asset-bounds.mjs');
});

test('fixture sanity: FURNITURE_SCALE and shell dims match the fixture meta', () => {
  assert.equal(FIXTURE.meta.furnitureScale, FURNITURE_SCALE);
  assert.equal(FIXTURE.meta.shell.width, 4);
  assert.equal(FIXTURE.meta.shell.depth, 3);
  assert.equal(FIXTURE.meta.gardenSize.width, 5);
  assert.equal(FIXTURE.meta.gardenSize.depth, 4);
  for (const [key, box] of Object.entries(FIXTURE.assets)) {
    for (let axis = 0; axis < 3; axis += 1) {
      assert.ok(box.max[axis] >= box.min[axis], `${key}: inverted bbox axis ${axis}`);
    }
  }
});

test('drift lock: pure computePlacedBoxes agrees with the live scene dump (≤ 0.05 m)', () => {
  const TOL = 0.05;
  let checked = 0;
  for (const def of DEFS) {
    const live = FIXTURE.livePlacedBoxes[def.id];
    assert.ok(live?.length, `${def.id}: fixture has no live placed boxes`);
    const pure = computePlacedBoxes(def, FIXTURE, { includeDressing: false });
    for (const row of live) {
      // merge multi-piece pure boxes (e.g. the wildflowers cluster) per entry
      const parts = pure.filter((b) => b.source === 'furniture' && b.index === row.index);
      assert.ok(parts.length, `${def.id}[${row.index}] ${row.name}: no pure box computed`);
      const merged = {
        min: [0, 1, 2].map((axis) => Math.min(...parts.map((b) => b.min[axis]))),
        max: [0, 1, 2].map((axis) => Math.max(...parts.map((b) => b.max[axis]))),
      };
      for (let axis = 0; axis < 3; axis += 1) {
        const drift = Math.max(
          Math.abs(merged.min[axis] - row.min[axis]),
          Math.abs(merged.max[axis] - row.max[axis])
        );
        assert.ok(
          drift <= TOL,
          `${def.id}[${row.index}] ${row.name}: pure/live drift ${drift.toFixed(4)} m on axis ${axis}`
          + ' — roomManager placement chain changed? regenerate the fixture + re-audit'
        );
      }
      checked += 1;
    }
  }
  assert.ok(checked >= 60, `only ${checked} live boxes checked — dump looks truncated`);
});

test('drift lock: the pinned V4/G52 radio extra matches the live fixture spot (≤ 0.05 m)', () => {
  // roomManager.js hard-codes the radio fixture at (−0.15, 0.52, −1.2) —
  // AUDIT_RULES.living.extras must stay in sync so the audit sees the real box.
  const liveBox = FIXTURE.meta.radioBox;
  assert.ok(liveBox, 'fixture meta.radioBox missing — regenerate');
  const extras = AUDIT_RULES.rooms.living.extras;
  const pure = computePlacedBoxes(LIVING, FIXTURE, { includeDressing: false, extras })
    .find((b) => b.source === 'extra');
  assert.ok(pure, 'living radio extra not replayed');
  for (let axis = 0; axis < 3; axis += 1) {
    assert.ok(Math.abs(pure.min[axis] - liveBox.min[axis]) <= 0.05
      && Math.abs(pure.max[axis] - liveBox.max[axis]) <= 0.05,
    `radio extra drift on axis ${axis}: pure [${pure.min[axis]}, ${pure.max[axis]}] `
      + `vs live [${liveBox.min[axis]}, ${liveBox.max[axis]}]`);
  }
});

test('tolerances stay honest: the clip threshold cannot silently balloon', () => {
  // 3.5 cm is the visual bar agreed in V4/AC-3D — anything looser lets real
  // interpenetration ship; anything tighter flags deliberate flush fits.
  assert.equal(DEFAULT_TOLERANCES.clipTol, 0.035);
  assert.equal(AUDIT_RULES.global.clipTol ?? DEFAULT_TOLERANCES.clipTol, 0.035);
  // V4/FIX-3D: allowances stay BOUNDED — 0.30 m clears the deepest deliberate
  // composition (the bedroom bear, 0.271 m inside the bed's canopy-style AABB)
  // while flagging the 0.32 m garden clip class. Looser and that bug ships again.
  assert.equal(DEFAULT_TOLERANCES.clipAllowMax, 0.3);
  assert.equal(AUDIT_RULES.global.clipAllowMax ?? DEFAULT_TOLERANCES.clipAllowMax, 0.3);
});
