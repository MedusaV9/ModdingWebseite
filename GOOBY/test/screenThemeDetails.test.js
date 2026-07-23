// GOOBY V6/B3 — screen-world detail tests (PLAN6 Wave B / B3).
// Pure node:test (no DOM, per AGENTS.md): the profile passport's MRZ footer
// formatter (fixed width, '<' padding, hard truncation, [A-Z0-9<] charset,
// DE transliteration), the album's deterministic polaroid tilt, the shop
// aisle-sign string completeness (every category tab has an EN+DE sign),
// EN/DE dictionary parity for the v6-screen-themes module, and source-scan
// guards: the V5 locked-sticker "no <img> while locked" invariant must stay
// untouched in albumScreen.js, and the platform-doc crash skin AssetIds
// 300001/300004/300006 must never enter shopScreen.js.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { EN, DE } from '../src/data/strings/v6-screen-themes.js';
import { mrzLines, MRZ_WIDTH } from '../src/ui/profileScreen.js';
import { polaroidJitter } from '../src/ui/albumScreen.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = (rel) => fs.readFileSync(path.join(ROOT, ...rel.split('/')), 'utf8');

// ---------------------------------------------------------------------------
// Passport MRZ footer (profileScreen.mrzLines)
// ---------------------------------------------------------------------------

test('B3 MRZ: two lines, always exactly MRZ_WIDTH chars, charset [A-Z0-9<]', () => {
  for (const d of [
    {},
    { name: 'Gooby', level: 3, joined: 1719800000000, skin: 'classic' },
    { name: 'x'.repeat(80), level: 999, joined: Date.now(), skin: 'GOLDEN sparkle fur deluxe edition' },
    { name: '', level: 0, joined: NaN, skin: null },
  ]) {
    const lines = mrzLines(d);
    assert.equal(lines.length, 2);
    for (const line of lines) {
      assert.equal(line.length, MRZ_WIDTH, `"${line}" must be exactly ${MRZ_WIDTH} chars`);
      assert.match(line, /^[A-Z0-9<]+$/, `"${line}" must only use the MRZ charset`);
    }
  }
});

test('B3 MRZ: short data pads with "<", long data hard-truncates', () => {
  const [short] = mrzLines({ name: 'Bo', level: 1 });
  assert.ok(short.startsWith('P<GBYBO<<LVL1'), short);
  assert.ok(short.endsWith('<'), 'padding filler is "<"');
  const [long] = mrzLines({ name: 'Maximiliana Gooberton The Third Of Snackville', level: 12 });
  assert.equal(long.length, MRZ_WIDTH);
  assert.ok(long.startsWith('P<GBYMAXIMILIANA'), long);
});

test('B3 MRZ: charset mapping — umlaut transliteration + "<" run collapse', () => {
  const [l1] = mrzLines({ name: 'Bö-bo müßig!! jr.', level: 2 });
  // Ö→OE, ü→UE, ß→SS; every non-alphanumeric RUN collapses to a single '<'
  assert.ok(l1.includes('BOE<BO<MUESSIG<JR'), l1);
  assert.ok(!l1.includes('<<<LVL'), 'no filler inflation before the level field');
});

test('B3 MRZ: real data lands in the fields (level, joined date, skin)', () => {
  const [l1, l2] = mrzLines({ name: 'Gooby', level: 12, joined: Date.UTC(2025, 4, 7), skin: 'Honey' });
  assert.ok(l1.includes('<<LVL12'), l1);
  assert.ok(l2.startsWith('20250507<HONEY<<GOOBY<PASS'), l2);
  // determinism: same input, same lines (UTC date parts — no TZ drift)
  assert.deepEqual(mrzLines({ name: 'Gooby', level: 12, joined: Date.UTC(2025, 4, 7), skin: 'Honey' }), [l1, l2]);
});

test('B3 MRZ: degenerate input falls back to GOOBY / zero date', () => {
  const [l1, l2] = mrzLines({ name: '!!!', level: -5, joined: 'nope' });
  assert.ok(l1.startsWith('P<GBYGOOBY<<LVL1'), l1);
  assert.ok(l2.startsWith('19700101<'), l2); // Number('nope')||0 → epoch, UTC
});

// ---------------------------------------------------------------------------
// Album polaroid tilt (albumScreen.polaroidJitter)
// ---------------------------------------------------------------------------

test('B3 polaroid jitter: deterministic per index (re-renders never shiver)', () => {
  for (let i = 0; i < 40; i += 1) {
    assert.equal(polaroidJitter(i), polaroidJitter(i), `index ${i} must be stable`);
  }
  assert.deepEqual(
    [0, 1, 2, 3].map(polaroidJitter),
    [0, 1, 2, 3].map(polaroidJitter),
  );
});

test('B3 polaroid jitter: bounded, never flat, neighbours lean apart', () => {
  const seen = new Set();
  for (let i = 0; i < 40; i += 1) {
    const deg = polaroidJitter(i);
    assert.ok(Number.isFinite(deg));
    assert.ok(Math.abs(deg) <= 2.2, `|${deg}| must stay subtle (≤2.2°)`);
    assert.ok(Math.abs(deg) >= 0.8, `|${deg}| must be visible (≥0.8°) — no flat polaroids`);
    assert.ok(Math.abs(deg * 10 - Math.round(deg * 10)) < 1e-9, 'one decimal place');
    // grid neighbours alternate direction — the wall reads hand-pinned
    assert.ok(polaroidJitter(i) * polaroidJitter(i + 1) < 0, `${i}/${i + 1} must lean apart`);
    seen.add(deg);
  }
  assert.ok(seen.size >= 8, 'magnitudes vary across the wall');
});

test('B3 polaroid jitter: junk input degrades to a finite tilt', () => {
  for (const junk of [undefined, null, NaN, 'x', -3, 2.7]) {
    assert.ok(Number.isFinite(polaroidJitter(junk)), `junk ${String(junk)}`);
  }
});

test('B3 polaroid jitter: albumScreen wires --b3-tilt from the helper', () => {
  const src = source('src/ui/albumScreen.js');
  assert.ok(src.includes("setProperty('--b3-tilt', `${polaroidJitter(idx)}deg`)"),
    'the Fotos grid must set the tilt custom property per index');
  assert.ok(src.includes("cell.className = 'g59-ph-cell b3-polaroid'"),
    'photo cells must carry the polaroid class');
});

// ---------------------------------------------------------------------------
// Shop aisle signs — completeness against the REAL category tab table
// ---------------------------------------------------------------------------

/** Category ids parsed from shopScreen's TABS table (id + shop.tab.* pairs). */
function shopTabIds() {
  const src = source('src/ui/shopScreen.js');
  const ids = [];
  for (const m of src.matchAll(/\[\s*'(\w+)',\s*'shop\.tab\.(\w+)'/g)) {
    assert.equal(m[1], m[2], `TABS id/label mismatch: ${m[0]}`);
    ids.push(m[1]);
  }
  return ids;
}

test('B3 aisle signs: every shop category tab has an EN+DE sign string', () => {
  const ids = shopTabIds();
  assert.ok(ids.length >= 6, `expected the 6 category tabs, parsed ${ids.length}`);
  for (const known of ['food', 'care', 'furniture', 'decor', 'outfits', 'skins']) {
    assert.ok(ids.includes(known), `TABS table lost the '${known}' category`);
  }
  for (const id of ids) {
    const key = `thm.shop.aisle.${id}`;
    assert.ok(typeof EN[key] === 'string' && EN[key].trim(), `EN missing ${key}`);
    assert.ok(typeof DE[key] === 'string' && DE[key].trim(), `DE missing ${key}`);
  }
  // and the screen actually renders the sign off the active tab id
  assert.ok(source('src/ui/shopScreen.js').includes('thm.shop.aisle.${tab}'),
    'shopScreen must build the aisle sign from the active tab id');
});

test('B3 strings: EN/DE parity, thm.* namespace, placeholder parity', () => {
  assert.deepEqual(Object.keys(EN).sort(), Object.keys(DE).sort());
  for (const [key, value] of Object.entries(EN)) {
    assert.ok(key.startsWith('thm.'), `${key} must live in the thm.* namespace`);
    const ph = (s) => (s.match(/\{\w+\}/g) ?? []).sort();
    assert.deepEqual(ph(DE[key]), ph(value), `placeholder mismatch in ${key}`);
  }
});

// ---------------------------------------------------------------------------
// Source-scan guards (V5 locked-sticker rule + platform skin exclusions)
// ---------------------------------------------------------------------------

test('B3 guard: locked stickers still render the mystery box, never <img>', () => {
  const src = source('src/ui/albumScreen.js');
  // the V5 mystery placeholder branch must survive at every render site
  // (book slot, secret slot, detail sheet, secret sheet)
  const mystery = src.match(/g34-sb-mystery" aria-hidden="true">\?<\/span>/g) ?? [];
  assert.ok(mystery.length >= 4, `mystery "?" branch found ${mystery.length}× (need ≥4)`);
  // every sticker-art <img> in the file (slot art g34-sb-art + sheet art
  // g34-sb-card-art) must be the unlocked arm of a `${unlocked ? ...}`
  // ternary — an unconditional art <img> would fetch (and expose) locked
  // art, regressing the V5 rule.
  let found = 0;
  for (const m of src.matchAll(/<img class="g34-sb-(?:card-)?art/g)) {
    found += 1;
    const before = src.slice(Math.max(0, m.index - 160), m.index);
    assert.match(before, /unlocked\s*\n?\s*\?\s*`?$/,
      `sticker <img> at offset ${m.index} is not guarded by the unlocked ternary`);
  }
  assert.equal(found, 4, `expected the 4 guarded sticker <img> sites, found ${found}`);
});

test('B3 guard: crash skin AssetIds 300001/300004/300006 stay out of shopScreen', () => {
  // Platform gotcha: those AssetIds are empty SkinData slots that crash the
  // locker UI — they have never existed in this codebase and this guard
  // keeps any future skin-catalog work from introducing them.
  const src = source('src/ui/shopScreen.js');
  for (const id of ['300001', '300004', '300006']) {
    assert.ok(!src.includes(id), `forbidden skin AssetId ${id} found in shopScreen.js`);
  }
});
