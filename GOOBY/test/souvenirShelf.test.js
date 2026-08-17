// V6.1/G2 (A3) — souvenir shelf: one procedural mini per visited vacation
// destination on a fixed living-room wall shelf, everything merged into ONE
// vertex-colored draw call (src/home/souvenirShelf.js).
//
// Locked here:
//   * recipe completeness — every VACATION_IDS destination owns exactly one
//     DISTINCT frozen mini spec built only from known primitive shapes;
//   * visited normalization + signature — junk in, clean known-ids map out,
//     key-order independent (the rebuild trigger can't misfire);
//   * the FROZEN G1 contract read (`vacation.sliceOf(state).visited`) with
//     the defensive raw-field/missing-map fallbacks;
//   * 0/1/4/9 build states — deterministic slots, single merged geometry,
//     and the ENVELOPE INVARIANT (identical AABB with 0 or 9 minis — what
//     keeps the generated `proc:souvenirShelf` fixture box valid for every
//     save state);
//   * controller lifecycle — rebuild ONLY on signature change, geometry
//     disposed on every re-merge, geometry + material disposed on dispose().
//
// three.js runs headlessly under node here (same as roomManager imports in
// rooms.test.js) — no DOM/GL is touched by geometry-only builds.

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  SHELF, MINI_SPECS, normalizeVisited, visitedSignature, readVisited,
  buildShelfGeometry, createSouvenirShelf,
} from '../src/home/souvenirShelf.js';
import { VACATION_IDS } from '../src/data/vacations.js';

const ALL_VISITED = Object.fromEntries(VACATION_IDS.map((id) => [id, true]));
const KNOWN_SHAPES = new Set(['box', 'sphere', 'cyl', 'cone', 'ico', 'oct']);

// ---------------------------------------------------------------------------
// recipe (pure data)
// ---------------------------------------------------------------------------

test('recipe: exactly one frozen mini spec per known destination id', () => {
  assert.deepEqual(Object.keys(MINI_SPECS).sort(), [...VACATION_IDS].sort());
  for (const [id, spec] of Object.entries(MINI_SPECS)) {
    assert.ok(Object.isFrozen(spec), `${id}: spec not frozen`);
    assert.ok(spec.length >= 1, `${id}: empty recipe`);
    for (const piece of spec) {
      assert.ok(Object.isFrozen(piece), `${id}: piece not frozen`);
      assert.ok(KNOWN_SHAPES.has(piece.shape), `${id}: unknown shape '${piece.shape}'`);
      assert.ok(typeof piece.color === 'string' && piece.color.startsWith('#'),
        `${id}: piece needs a hex color`);
      assert.equal(piece.at.length, 3, `${id}: piece.at must be [x,y,z]`);
    }
  }
});

test('recipe: all nine minis are visually distinct (no copy-pasted keepsake)', () => {
  const fingerprints = Object.values(MINI_SPECS).map((spec) =>
    JSON.stringify(spec.map((p) => [p.shape, p.size, p.color])));
  assert.equal(new Set(fingerprints).size, fingerprints.length, 'two destinations share a mini recipe');
});

test('recipe: every mini stays inside the shelf envelope (plank footprint + under the backboard top)', () => {
  // the audit contract: minis may never poke outside the plank/backboard AABB
  for (const [id, spec] of Object.entries(MINI_SPECS)) {
    for (const piece of spec) {
      const r = Math.max(...piece.size) * Math.max(...(piece.scale ?? [1, 1, 1]));
      assert.ok(Math.abs(piece.at[0]) <= 0.075, `${id}: piece x offset escapes the slot`);
      assert.ok(piece.at[1] + r <= SHELF.BACK.H, `${id}: piece can rise above the backboard top`);
      assert.ok(Math.abs(piece.at[2]) <= SHELF.PLANK.D / 2, `${id}: piece z offset escapes the plank`);
    }
  }
});

// ---------------------------------------------------------------------------
// visited normalization + signature (the rebuild trigger)
// ---------------------------------------------------------------------------

test('normalizeVisited: junk-shaped input always yields a clean known-ids map', () => {
  assert.deepEqual(normalizeVisited(null), {});
  assert.deepEqual(normalizeVisited(undefined), {});
  assert.deepEqual(normalizeVisited(['beach']), {});
  assert.deepEqual(normalizeVisited('beach'), {});
  assert.deepEqual(normalizeVisited({ beach: 1, space: 'yes' }), {}); // truthy ≠ true
  assert.deepEqual(normalizeVisited({ atlantis: true }), {}); // unknown id never builds
  assert.deepEqual(
    normalizeVisited({ beach: true, atlantis: true, space: false, harbor: true }),
    { beach: true, harbor: true }
  );
});

test('visitedSignature: stable under key order + junk; changes only on real progress', () => {
  assert.equal(visitedSignature(null), '');
  assert.equal(visitedSignature({}), '');
  assert.equal(
    visitedSignature({ space: true, beach: true }),
    visitedSignature({ beach: true, space: true, atlantis: true })
  );
  assert.notEqual(
    visitedSignature({ beach: true }),
    visitedSignature({ beach: true, space: true })
  );
});

test('readVisited: sliceOf contract first, raw-field fallback, missing map = empty', () => {
  // normalized G1 slice shape (post-G1 saves)
  assert.deepEqual(
    readVisited({ vacation: { visited: { beach: true, atlantis: true } } }),
    { beach: true }
  );
  // pre-contract saves / no vacation slice at all → defensive empty
  assert.deepEqual(readVisited({}), {});
  assert.deepEqual(readVisited(null), {});
  assert.deepEqual(readVisited({ vacation: null }), {});
  assert.deepEqual(readVisited({ vacation: { phase: 'none' } }), {});
});

// ---------------------------------------------------------------------------
// geometry build states (0 / 1 / 4 / 9) + the envelope invariant
// ---------------------------------------------------------------------------

const bbox = (geo) => {
  geo.computeBoundingBox();
  const b = geo.boundingBox;
  return [...b.min.toArray(), ...b.max.toArray()].map((v) => +v.toFixed(5) || 0); // || 0 folds −0
};

test('build: 0/1/4/9 states merge into one geometry with position/normal/color only', () => {
  const states = [
    {},
    { beach: true },
    { beach: true, space: true, bakery: true, harbor: true },
    ALL_VISITED,
  ];
  let prevVerts = 0;
  for (const visited of states) {
    const geo = buildShelfGeometry(visited);
    assert.equal(geo.index, null, 'merged geometry must be non-indexed');
    assert.deepEqual(
      Object.keys(geo.attributes).sort(), ['color', 'normal', 'position'],
      'merged attributes must stay position/normal/color'
    );
    const verts = geo.getAttribute('position').count;
    assert.ok(verts > prevVerts, 'more souvenirs must add vertices');
    prevVerts = verts;
    geo.dispose();
  }
});

test('build: envelope invariant — the AABB with 9 minis equals the empty shelf AABB', () => {
  const empty = buildShelfGeometry({});
  const full = buildShelfGeometry(ALL_VISITED);
  assert.deepEqual(bbox(full), bbox(empty),
    'a mini escapes the plank/backboard envelope — the generated proc:souvenirShelf fixture box would drift by save state');
  // and the envelope is exactly the documented plank/backboard extents
  assert.deepEqual(bbox(empty), [
    -SHELF.PLANK.W / 2, 0, -SHELF.PLANK.D / 2,
    SHELF.PLANK.W / 2, SHELF.BACK.H, SHELF.PLANK.D / 2,
  ]);
  empty.dispose();
  full.dispose();
});

test('build: deterministic slots — a mini never moves when its neighbours appear', () => {
  // merge order is plank, backboard, then minis in VACATION_IDS order, so
  // the LAST mini's trailing vertex block is comparable across visited sets.
  const tail = (geo) =>
    Array.from(geo.getAttribute('position').array.slice(-300)).map((v) => +v.toFixed(5));
  const alone = buildShelfGeometry({ space: true });
  const crowded = buildShelfGeometry({ beach: true, meadowTrip: true, space: true });
  assert.deepEqual(tail(crowded), tail(alone),
    'the space rock moved when beach/meadow minis appeared — slots must be fixed');
  alone.dispose();
  crowded.dispose();
});

// ---------------------------------------------------------------------------
// controller lifecycle (rebuild-on-signature + disposal)
// ---------------------------------------------------------------------------

test('controller: builds once, rebuilds ONLY on signature change, disposes replaced geometry', () => {
  let visited = {};
  const shelf = createSouvenirShelf(() => visited);
  assert.equal(shelf.group.children.length, 1, 'one merged mesh — one draw call');
  const firstGeo = shelf.group.children[0].geometry;
  assert.equal(shelf.signature(), '');

  // same signature (junk + key order changes included) → NO rebuild
  visited = { atlantis: true };
  assert.equal(shelf.refresh(), false);
  assert.equal(shelf.group.children[0].geometry, firstGeo, 'geometry must be untouched');

  // real progress → rebuild, old geometry disposed, material SHARED
  let disposed = 0;
  const origDispose = firstGeo.dispose.bind(firstGeo);
  firstGeo.dispose = () => { disposed += 1; origDispose(); };
  const firstMat = shelf.group.children[0].material;
  visited = { beach: true };
  assert.equal(shelf.refresh(), true);
  assert.equal(disposed, 1, 'replaced geometry must be disposed');
  assert.equal(shelf.signature(), 'beach');
  assert.equal(shelf.group.children[0].material, firstMat, 'material is created once and shared');
  assert.equal(shelf.group.children.length, 1, 'still exactly one mesh');
  shelf.dispose();
});

test('controller: dispose() empties the group and frees geometry + material exactly once', () => {
  const shelf = createSouvenirShelf(() => ALL_VISITED);
  const mesh = shelf.group.children[0];
  let geoDisposed = 0;
  let matDisposed = 0;
  const geoOrig = mesh.geometry.dispose.bind(mesh.geometry);
  const matOrig = mesh.material.dispose.bind(mesh.material);
  mesh.geometry.dispose = () => { geoDisposed += 1; geoOrig(); };
  mesh.material.dispose = () => { matDisposed += 1; matOrig(); };
  shelf.dispose();
  assert.equal(shelf.group.children.length, 0);
  assert.equal(geoDisposed, 1);
  assert.equal(matDisposed, 1);
  assert.equal(shelf.signature(), null, 'signature resets so a revived controller would rebuild');
});
