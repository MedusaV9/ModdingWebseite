// V6.1 FINAL WAVE (G1) — depth / travel-spine UI + strings suite. Pure
// node:test per §B: the v6_1-content string module (parity, spread wiring,
// collision safety with every module it sits next to), the A2 teaser
// mystery contract, the B4 weather welcome-home trio against the real
// deterministic weatherAt, the B2/C3 template shapes, and source-scan pins
// for the browser-only seams (airportScreen locked cards + Reisepass chip +
// celebrate() weather toast, profileScreen park stamps, parkScene's
// completion-only wheel recording) — the same §E0.1-10 marker-pin protocol
// recapOverlay.test.js / loadingVeil.test.js already use.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { EN, DE } from '../src/data/strings.js';
import { EN as V61_EN, DE as V61_DE } from '../src/data/strings/v6_1-content.js';
import { EN as V5VAC_EN } from '../src/data/strings/v5-vacation.js';
import { EN as V6VAC_EN } from '../src/data/strings/v6-vacations.js';
import { EN as V6VACC_EN } from '../src/data/strings/v6-vacation-content.js';
import { EN as THM_EN } from '../src/data/strings/v6-screen-themes.js';
import { EN as PARK_EN } from '../src/data/strings/v6-park.js';
import { VACATION_IDS } from '../src/data/vacations.js';
import { weatherAt } from '../src/systems/weather.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = (rel) => fs.readFileSync(path.join(ROOT, ...rel.split('/')), 'utf8');

// ---------------------------------------------------------------------------
// strings/v6_1-content.js — the single shared V6.1 module
// ---------------------------------------------------------------------------

test('V6.1 strings: EN and DE carry the exact same key set, all non-empty', () => {
  assert.deepEqual(Object.keys(V61_EN).sort(), Object.keys(V61_DE).sort());
  for (const [key, value] of [...Object.entries(V61_EN), ...Object.entries(V61_DE)]) {
    assert.ok(typeof value === 'string' && value.length > 0, `${key}: empty`);
  }
});

test('V6.1 strings: the module is spread into the merged dictionaries LAST', () => {
  for (const key of Object.keys(V61_EN)) {
    assert.equal(EN[key], V61_EN[key], `EN merged dict misses/overrides ${key}`);
    assert.equal(DE[key], V61_DE[key], `DE merged dict misses/overrides ${key}`);
  }
});

test('V6.1 strings: never shadow the v5/v6 modules they sit next to', () => {
  // a duplicate key would silently mask the earlier module (v6_1 spreads
  // last) — the acui collision-safety precedent, applied to every dictionary
  // this module shares a namespace prefix with
  for (const [name, dict] of [
    ['v5-vacation', V5VAC_EN],
    ['v6-vacations', V6VAC_EN],
    ['v6-vacation-content', V6VACC_EN],
    ['v6-screen-themes', THM_EN],
    ['v6-park', PARK_EN],
  ]) {
    for (const key of Object.keys(V61_EN)) {
      assert.ok(!(key in dict), `${key} defined in both v6_1-content and ${name}`);
    }
  }
});

test('V6.1 strings: the G2/G3 manifest keys all landed (handoff contract)', () => {
  const manifest = [
    'secret.ducky', // G2/B7
    'cutscene.versary.month.title', 'cutscene.versary.month.dance',
    'cutscene.versary.month.thanks', 'cutscene.versary.year.title',
    'cutscene.versary.year.memories', 'cutscene.versary.year.confetti',
    'cutscene.versary.year.thanks', // G3/B5
    'gallery.frame.park', 'park.wheel.apexNight', 'settings.loveNote', // G3/B6+B8+B1
    ...VACATION_IDS.flatMap((id) => [
      `vacation.postcard.${id}.4`, `vacation.postcard.${id}.5`, // G3/B3
    ]),
  ];
  for (const key of manifest) {
    assert.ok(key in V61_EN, `EN manifest key ${key} missing`);
    assert.ok(key in V61_DE, `DE manifest key ${key} missing`);
  }
  // the B1 love note keeps its {heart} placeholder verbatim (the ♥ glyph
  // span is authored in settingsScreen.js, G3's side of the seam)
  assert.ok(V61_EN['settings.loveNote'].includes('{heart}'));
  assert.ok(V61_DE['settings.loveNote'].includes('{heart}'));
});

// ---------------------------------------------------------------------------
// A2 — nine DISTINCT locked-card teasers under the mystery contract
// ---------------------------------------------------------------------------

test('V6.1/A2 teasers: nine distinct lines per language, one per destination', () => {
  for (const [lang, dict] of [['EN', V61_EN], ['DE', V61_DE]]) {
    const lines = VACATION_IDS.map((id) => {
      const line = dict[`vacation.dest.${id}.teaser`];
      assert.ok(typeof line === 'string' && line.length > 0, `${lang} teaser missing for ${id}`);
      return line;
    });
    assert.equal(new Set(lines).size, lines.length, `${lang}: teasers must be pairwise distinct`);
  }
});

test('V6.1/A2 teasers: no destination name / price / days / unlock digit leaks', () => {
  const names = VACATION_IDS
    .flatMap((id) => [EN[`vacation.dest.${id}.name`], DE[`vacation.dest.${id}.name`]])
    .filter(Boolean);
  for (const dict of [V61_EN, V61_DE]) {
    for (const id of VACATION_IDS) {
      const line = dict[`vacation.dest.${id}.teaser`];
      for (const name of names) {
        assert.ok(!line.includes(name), `teaser for ${id} leaks '${name}'`);
      }
      // prices/days/gate levels are all numerals — a teaser never carries one
      assert.ok(!/\d/.test(line), `teaser for ${id} leaks a number: '${line}'`);
    }
  }
});

test('V6.1/A2 wiring: locked cards render the teaser, no glyph/accent/data-dest', () => {
  const air = source('src/ui/airportScreen.js');
  // the locked branch reads the per-destination teaser key…
  assert.match(air, /v5-air-locked[\s\S]{0,300}?vacation\.dest\.\$\{d\.id\}\.teaser/);
  // …behind the generic lock glyph and the '???' name (unchanged contract)
  assert.match(air, /v5-air-locked" aria-disabled="true">\s*\r?\n\s*\$\{icon\('lock', 26\)\}/);
  // no data-dest / accent style / catalog glyph before unlock: those tokens
  // appear only in the unlocked <button> branch
  const lockedBlock = air.match(/v5-air-locked" aria-disabled="true">[\s\S]*?<\/div>`;/)?.[0] ?? '';
  assert.ok(lockedBlock.length > 0, 'locked card block found');
  assert.ok(!lockedBlock.includes('data-dest'), 'locked card carries no click target');
  assert.ok(!lockedBlock.includes('--v5-air-accent'), 'locked card carries no accent');
  assert.ok(!lockedBlock.includes('d.icon'), 'locked card carries no destination glyph');
});

// ---------------------------------------------------------------------------
// B4 — deterministic weather welcome-home line
// ---------------------------------------------------------------------------

test('V6.1/B4: every reachable weather state has its welcome-home line (EN+DE)', () => {
  for (const state of ['clear', 'cloudy', 'rain']) {
    assert.ok(V61_EN[`vacation.home.${state}`], `EN vacation.home.${state}`);
    assert.ok(V61_DE[`vacation.home.${state}`], `DE vacation.home.${state}`);
  }
  // the real weatherAt only ever produces those three states — sample a
  // spread of deterministic timestamps across days and block boundaries
  const T0 = Date.UTC(2026, 6, 16, 0, 30, 0);
  for (let i = 0; i < 200; i += 1) {
    const { state } = weatherAt(T0 + i * 5.5 * 3600000);
    assert.ok(['clear', 'cloudy', 'rain'].includes(state), `unmapped state '${state}'`);
  }
});

test('V6.1/B4 wiring: celebrate() queues ONE weather line right after the welcome toast', () => {
  const air = source('src/ui/airportScreen.js');
  assert.match(air, /import \{ weatherAt \} from '\.\.\/systems\/weather\.js'/);
  assert.match(
    air,
    /ui\.toast\('vacation\.welcomeBack', \{ coins: res\.souvenir \?\? 0 \}\);[\s\S]{0,600}?ui\.toast\(`vacation\.home\.\$\{weatherAt\(now\(\)\)\.state\}`\);/,
    'weather line queues sequentially after vacation.welcomeBack'
  );
  // exactly one weather-toast call site (celebrate runs once per reunion,
  // for both the pickup and the taxi path)
  assert.equal((air.match(/vacation\.home\.\$\{/g) ?? []).length, 1);
});

// ---------------------------------------------------------------------------
// B2 — passport stamps  /  C3 — Reisepass chip
// ---------------------------------------------------------------------------

test('V6.1/B2 strings: both stamps interpolate {n}; park name is the proper noun', () => {
  for (const dict of [V61_EN, V61_DE]) {
    assert.ok(dict['thm.passport.stamp.park'].includes('{n}'));
    assert.ok(dict['thm.passport.stamp.wheel'].includes('{n}'));
    assert.ok(dict['thm.passport.stamp.park'].startsWith('Funkelpark'));
  }
  assert.equal(V61_DE['thm.passport.stamp.wheel'], 'Riesenrad ×{n}');
});

test('V6.1/B2 wiring: stamps ride the normalized park slice behind > 0 guards', () => {
  const prof = source('src/ui/profileScreen.js');
  assert.match(prof, /import \{ sliceOf as parkSliceOf \} from '\.\.\/systems\/themePark\.js'/);
  assert.match(prof, /const park = parkSliceOf\(state\);/);
  // old saves (0 visits / 0 wheel rides) push NEITHER stamp
  assert.match(prof, /if \(park\.visits > 0\) stamps\.push\(tx\('thm\.passport\.stamp\.park', \{ n: park\.visits \}\)\)/);
  assert.match(prof, /if \(park\.rides\.wheel > 0\) stamps\.push\(tx\('thm\.passport\.stamp\.wheel', \{ n: park\.rides\.wheel \}\)\)/);
  // the fourth/fifth stamp rows keep the hand-stamped rotation rhythm
  assert.match(prof, /\.b3-pass-stamp\.ac-stamp:nth-child\(4\)\{transform:rotate\(/);
  assert.match(prof, /\.b3-pass-stamp\.ac-stamp:nth-child\(5\)\{transform:rotate\(/);
});

test('V6.1/C3 strings + wiring: the Reisepass chip is bounded n/9 by construction', () => {
  for (const dict of [V61_EN, V61_DE]) {
    const tpl = dict['vacation.pass.progress'];
    assert.ok(tpl.includes('{n}') && tpl.includes('{total}'), `chip template: '${tpl}'`);
  }
  assert.ok(V61_DE['vacation.pass.progress'].startsWith('Reisepass'));
  const air = source('src/ui/airportScreen.js');
  // count comes from the sliceOf-normalized visited map (capped at the nine
  // catalog ids — junk saves can never inflate the chip)
  assert.match(air, /const visitedCount = Object\.keys\(v\.visited\)\.length;/);
  assert.match(air, /const passDone = visitedCount >= VACATION_IDS\.length;/);
  assert.match(air, /vacation\.pass\.progress', \{ n: visitedCount, total: VACATION_IDS\.length \}/);
  // 9/9 flips to the golden complete look
  assert.match(air, /v6-pass-chip\$\{passDone \? ' v6-pass-chip-done' : ''\}/);
  assert.match(air, /\.v6-pass-chip-done\{/);
});

// ---------------------------------------------------------------------------
// C1 — the wheel records on COMPLETION only (parkScene wiring)
// ---------------------------------------------------------------------------

test("V6.1/C1 wiring: kickWheelRide records 'wheel' once, in onDone, completions only", () => {
  const park = source('src/park/parkScene.js');
  // exactly ONE 'wheel' recordRide write site in the whole scene
  const writes = park.match(/recordRide\(s\.themePark, 'wheel'\)/g) ?? [];
  assert.equal(writes.length, 1, "one 'wheel' write site");
  // the write sits INSIDE onDone, behind the started flag AND the
  // entered/gooby guard (exit() clears `entered` BEFORE cancelRide, so an
  // interrupted ride never records; a refused start never flips the flag)
  assert.match(
    park,
    /onDone: \(\) => \{[\s\S]{0,700}?if \(!entered \|\| !gooby\) return;[\s\S]{0,300}?if \(rideStarted\) \{[\s\S]{0,300}?recordRide\(s\.themePark, 'wheel'\)/,
    'completion-only guard chain'
  );
  // the flag flips true only after startWheelRide resolved ok
  assert.match(park, /if \(!ok\) wheelRiding = false;\r?\n\s*else rideStarted = true;/);
});
