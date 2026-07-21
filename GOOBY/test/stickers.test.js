// V3/G34 — sticker catalog integrity (PLAN3 §C5.1/§C5.2, binding). THE WAVE
// GATE: catalog ↔ committed PNG 1:1 (fails on missing OR extra files), every
// art 512×512 ≤ 150 KB (§C5.2/§D6), the frozen ids in table order (28 §C5.1
// originals + 20 V5/STICKERS wave-1 appends + the secret slot last), every
// condition row verbatim against an independent spec copy, EN/DE
// title/flavor/hint parity, and — via the pure engine — all 48 unlockable
// through their real condition shapes.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';

import {
  STICKERS, STICKERS_BY_ID, getSticker, TOTAL_BOOK_STICKERS,
  STICKER_PAGE_SIZES, stickerPages,
} from '../src/data/stickers.js';
import {
  stickerProgress, isStickerSatisfied, applyStickerUnlocks,
} from '../src/systems/stickerBook.js';
import { defaultState } from '../src/core/save.js';
import { EN, DE } from '../src/data/strings.js';

const ART_DIR = new URL('../public/assets/stickers/', import.meta.url);

// --- §C5.1 spec copy (independent — catalog drift fails here) ---------------
// id → cond, in FROZEN table order.
const SPEC_CONDS = [
  ['firstNom', { counter: 'feeds', target: 1 }],
  ['squeakyClean', { counter: 'washes', target: 1 }],
  ['ballBuddy', { counter: 'balls', target: 10 }],
  ['sleepyhead', { counter: 'sleeps', target: 1 }],
  ['tenNights', { counter: 'sleeps', target: 10 }],
  ['grumpMorning', { event: 'grumpyWake' }],
  ['feverFace', { counter: 'sickEver', target: 1 }],
  ['drGooby', { counter: 'vetTrips', target: 1 }],
  ['firstSprout', { counter: 'harvests', target: 1 }],
  ['rainyDay', { event: 'rainCanopy' }],
  ['starGazer', { event: 'nightStars' }],
  ['sayCheese', { counter: 'photosTaken', target: 1 }],
  ['bigTen', { special: 'level', target: 10 }],
  ['quarterClub', { special: 'level', target: 25 }],
  ['maxLevel', { special: 'level', target: 40 }],
  ['roadTripper', { counter: 'trips', target: 1 }],
  ['towTrouble', { event: 'towed' }],
  ['goldenCatch', { special: 'collectionEntry', set: 'fish', entry: 'goldenFish', target: 1 }],
  ['discoGooby', { special: 'gameBest', game: 'danceParty', target: 100 }],
  ['holeInOneHero', { counter: 'holeInOnes', target: 1 }],
  ['parcelPro', { counter: 'deliveries', target: 10 }],
  ['freshDrip', { special: 'skinsOwned', target: 2 }],
  ['fullFit', { special: 'fullOutfit', target: 3 }],
  ['maxFloof', { special: 'weightMax', target: 86 }],
  ['nutellaGlob', { counter: 'nougatGlobs', target: 1 }],
  ['cakeBoss', { counter: 'perfectCakes', target: 1 }],
  ['surfStar', { counter: 'surfRuns', target: 1 }],
  ['albumMaster', { special: 'setsClaimed', target: 4 }],
  // V5/STICKERS wave 1: 20 new regular rows — EXISTING counter/gameBest
  // condition plumbing only (no new specials/hooks), appended after the 28
  // frozen §C5.1 rows and before the secret slot.
  ['snackStack', { counter: 'feeds', target: 50 }],
  ['cleanMachine', { counter: 'washes', target: 25 }],
  ['bellyLaugh', { counter: 'tickles', target: 50 }],
  ['dreamTeam', { counter: 'sleeps', target: 25 }],
  ['gardenBasket', { counter: 'harvests', target: 25 }],
  ['greenThumb', { counter: 'waterings', target: 50 }],
  ['seedStarter', { counter: 'plantings', target: 10 }],
  ['photoWall', { counter: 'photosTaken', target: 10 }],
  ['roadRegular', { counter: 'trips', target: 10 }],
  ['ballStorm', { counter: 'balls', target: 50 }],
  ['safeDriver', { counter: 'cleanTrips', target: 5 }],
  ['deliveryAce', { counter: 'deliveries', target: 50 }],
  ['modifierMischief', { counter: 'modifierPlays', target: 5 }],
  ['carrotChampion', { special: 'gameBest', game: 'carrotCatch', target: 60 }],
  ['memoryMaster', { special: 'gameBest', game: 'memoryMatch', target: 40 }],
  ['saysSuperstar', { special: 'gameBest', game: 'goobySays', target: 100 }],
  ['questScout', { counter: 'questsDone', target: 10 }],
  ['getWellSoon', { counter: 'cures', target: 3 }],
  ['radioBunny', { counter: 'radioMinutes', target: 30 }],
  ['codeWhisperer', { counter: 'codesRedeemed', target: 1 }],
  // V4/G53 (PLAN4 §C-SYS5.4/§B6): the secret BONUS sticker — outside the
  // regular count (secret: true), unlocked only via the 'herzGooby' code
  // word, LAST in table order.
  ['herzGooby', { code: 'herzGooby' }],
];

// ------------------------------------------------------------------ catalog

test('48 regular stickers + secret, ids in frozen table order, unique', () => {
  // V5/STICKERS: 28 §C5.1 originals + 20 wave-1 appends = 48 regular; the
  // secret herzGooby stays outside the count and LAST in table order.
  assert.equal(STICKERS.length, 49);
  assert.equal(TOTAL_BOOK_STICKERS, 48);
  assert.deepEqual(STICKERS.map((s) => s.id), SPEC_CONDS.map(([id]) => id));
  assert.equal(new Set(STICKERS.map((s) => s.id)).size, 49);
  assert.equal(getSticker('firstNom'), STICKERS[0]);
  assert.equal(getSticker('bogus'), undefined);
  // the ONE secret def is herzGooby, flagged + last in table order
  assert.deepEqual(STICKERS.filter((s) => s.secret).map((s) => s.id), ['herzGooby']);
  assert.equal(STICKERS[48].id, 'herzGooby');
  // the 28 §C5.1 originals stay FROZEN in their exact positions
  assert.equal(STICKERS[27].id, 'albumMaster');
  assert.equal(STICKERS[28].id, 'snackStack');
});

test('every condition row matches §C5.1 verbatim', () => {
  for (const [id, cond] of SPEC_CONDS) {
    assert.deepEqual({ ...STICKERS_BY_ID[id].cond }, cond, `cond for ${id}`);
  }
});

test('defs carry nameKey/flavorKey/hintKey/art in the §B5 shapes', () => {
  for (const s of STICKERS) {
    assert.equal(s.nameKey, `stickerbook.${s.id}.name`);
    assert.equal(s.flavorKey, `stickerbook.${s.id}.flavor`);
    assert.equal(s.hintKey, `stickerbook.${s.id}.hint`);
    assert.equal(s.art, `assets/stickers/${s.id}.png`);
    assert.ok(Object.isFrozen(s), `${s.id} frozen`);
    assert.ok(Object.isFrozen(s.cond), `${s.id}.cond frozen`);
  }
});

test('page layout: 8 pages of 6 (V5), table order preserved', () => {
  assert.deepEqual([...STICKER_PAGE_SIZES], [6, 6, 6, 6, 6, 6, 6, 6]);
  const pages = stickerPages();
  assert.deepEqual(pages.map((p) => p.length), [6, 6, 6, 6, 6, 6, 6, 6]);
  // V4/G53 (§C-SYS5.4): pages carry the 48 REGULAR defs only — the secret
  // slot is appended to the LAST page by ui/albumScreen.js, outside paging.
  assert.deepEqual(
    pages.flat().map((s) => s.id),
    STICKERS.filter((s) => !s.secret).map((s) => s.id)
  );
  assert.ok(pages.flat().every((s) => s.id !== 'herzGooby'));
});

test('every sticker title/flavor/hint exists in BOTH dictionaries (EN+DE)', () => {
  for (const s of STICKERS) {
    for (const key of [s.nameKey, s.flavorKey, s.hintKey]) {
      assert.equal(typeof EN[key], 'string', `EN missing ${key}`);
      assert.ok(EN[key].length > 0, `EN empty ${key}`);
      assert.equal(typeof DE[key], 'string', `DE missing ${key}`);
      assert.ok(DE[key].length > 0, `DE empty ${key}`);
    }
  }
  // §C5.1 verbatim spot checks (EN + DE title/flavor)
  assert.equal(EN['stickerbook.firstNom.name'], 'First Nom');
  assert.equal(DE['stickerbook.firstNom.name'], 'Erster Happs');
  assert.equal(EN['stickerbook.maxLevel.flavor'], 'There is no level 41. Gooby checked.');
  assert.equal(DE['stickerbook.maxLevel.flavor'], 'Es gibt kein Level 41. Gooby hat nachgesehen.');
  assert.equal(DE['stickerbook.albumMaster.name'], 'Album-Meister');
});

// ------------------------------------------- §C5.2 art files (the wave gate)

/** Parse width/height from a PNG's IHDR (bytes 16–23 after the signature). */
function pngSize(buf) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.deepEqual(buf.subarray(0, 8), sig, 'PNG signature');
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

test('catalog ↔ public/assets/stickers/*.png is exactly 1:1 (§C5.2 gate)', () => {
  const files = readdirSync(ART_DIR).filter((f) => f.endsWith('.png')).sort();
  const expected = STICKERS.map((s) => `${s.id}.png`).sort();
  assert.deepEqual(files, expected, 'no missing and no extra sticker art');
});

test('every sticker PNG is 512×512 and ≤ 150 KB (§C5.2/§D6)', () => {
  for (const s of STICKERS) {
    const url = new URL(`${s.id}.png`, ART_DIR);
    const bytes = statSync(url).size;
    assert.ok(bytes <= 150 * 1024, `${s.id}.png is ${bytes} B (> 150 KB)`);
    const { width, height } = pngSize(readFileSync(url));
    assert.equal(width, 512, `${s.id}.png width`);
    assert.equal(height, 512, `${s.id}.png height`);
  }
});

// ------------------------- all 28 unlockable via their REAL conditions (§B5)

/**
 * Build a state that legitimately satisfies every §C5.1 condition at once
 * (event stickers unlock via their hook path — asserted separately).
 */
function maxedState() {
  const s = defaultState();
  s.level = 40;
  s.weight.value = 86;
  Object.assign(s.achievements.counters, {
    // originals raised where a V5 sticker shares the counter (higher target
    // still satisfies the lower original — e.g. feeds 50 covers firstNom 1)
    feeds: 50, washes: 25, balls: 50, sleeps: 25, sickEver: 1, vetTrips: 1,
    harvests: 25, photosTaken: 10, trips: 10, holeInOnes: 1, deliveries: 50,
    nougatGlobs: 1, perfectCakes: 1, surfRuns: 1,
    // V5/STICKERS wave-1 counters (all existing §B1/§B2 keys)
    tickles: 50, waterings: 50, plantings: 10, cleanTrips: 5,
    modifierPlays: 5, questsDone: 10, cures: 3, radioMinutes: 30,
    codesRedeemed: 1,
  });
  s.minigames.best.danceParty = 100;
  // V5/STICKERS gameBest rows
  s.minigames.best.carrotCatch = 60;
  s.minigames.best.memoryMatch = 40;
  s.minigames.best.goobySays = 100;
  s.collections.entries['fish.goldenFish'] = 1;
  s.collections.claimedSets = { veggies: 1, fish: 1, landmarks: 1, treats: 1 };
  s.skins.owned = ['cream', 'snow'];
  s.outfits.equipped = { hat: 'crown', glasses: 'starGlasses', neck: 'scarfRed', back: null };
  s.codes.redeemed.herzGooby = 777; // V4/G53: secret unlocks via its code latch
  return s;
}

test('all 44 counter/special stickers unlock through applyStickerUnlocks', () => {
  const eventIds = SPEC_CONDS.filter(([, c]) => c.event).map(([id]) => id);
  assert.deepEqual(eventIds, ['grumpMorning', 'rainyDay', 'starGazer', 'towTrouble']);
  const { state, unlocked } = applyStickerUnlocks(maxedState(), 777);
  // 44 counter/special (24 original + 20 V5) + the code-latched secret = 45
  assert.equal(unlocked.length, SPEC_CONDS.length - eventIds.length);
  for (const [id, cond] of SPEC_CONDS) {
    if (cond.event) {
      assert.equal(state.stickers.unlocked[id], undefined, `${id} needs its hook`);
    } else {
      assert.equal(state.stickers.unlocked[id], 777, `${id} unlocked`);
    }
  }
});

test('each individual condition flips exactly at its threshold', () => {
  for (const [id, cond] of SPEC_CONDS) {
    if (cond.event) continue;
    const def = STICKERS_BY_ID[id];
    const below = defaultState();
    const at = maxedState();
    // build a below-threshold variant of the maxed state for THIS sticker
    if (cond.counter) {
      Object.assign(below.achievements.counters, at.achievements.counters);
      below.achievements.counters[cond.counter] = cond.target - 1;
    } else if (cond.special === 'level') below.level = cond.target - 1;
    else if (cond.special === 'weightMax') below.weight.value = cond.target - 1;
    else if (cond.special === 'setsClaimed') below.collections.claimedSets = { veggies: 1 };
    else if (cond.special === 'skinsOwned') below.skins.owned = ['cream'];
    else if (cond.special === 'gameBest') below.minigames.best[cond.game] = cond.target - 1;
    else if (cond.special === 'collectionEntry') below.collections.entries = {};
    else if (cond.special === 'fullOutfit') {
      below.outfits.equipped = { hat: 'crown', glasses: 'starGlasses', neck: null, back: null };
    }
    assert.equal(isStickerSatisfied(def, below), false, `${id} below threshold`);
    assert.equal(isStickerSatisfied(def, at), true, `${id} at threshold`);
    const p = stickerProgress(def, at);
    assert.equal(p.current, p.target, `${id} progress caps at target`);
  }
});
