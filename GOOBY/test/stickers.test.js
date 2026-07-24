// V3/G34 — sticker catalog integrity (PLAN3 §C5.1/§C5.2, binding). THE WAVE
// GATE: catalog ↔ committed PNG 1:1 (fails on missing OR extra files), every
// art 512×512 ≤ 150 KB (§C5.2/§D6), the frozen ids in table order (28 §C5.1
// originals + 20 V5/STICKERS wave-1 appends + 36 V6/F1 themed-page appends +
// the secret slot last), every condition row verbatim against an independent
// spec copy, the V6/F1 STICKER_PAGES presentation catalog, EN/DE
// title/flavor/hint parity, and — via the pure engine — all 84 unlockable
// through their real condition shapes.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';

import {
  STICKERS, STICKERS_BY_ID, getSticker, TOTAL_BOOK_STICKERS,
  STICKER_PAGE_SIZES, STICKER_PAGES, stickerPages,
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
  // V6/F1 (PLAN6 Wave F): 36 new regular rows on six themed pages, appended
  // after the 48 frozen pre-V6 rows and before the secret slot. Conditions
  // are PURE READS of existing slices only (postcard archive, vacation
  // trips, themePark, bests, counters, daily/profile/outfits/furniture).
  // NOTE: handsUp keys off rides.coaster ≥ 3 (no hands-up writer exists —
  // the ruled fallback; hint copy says so honestly).
  ['beachPostcard', { special: 'postcards', dest: 'beach', target: 1 }],
  ['harborPostcard', { special: 'postcards', dest: 'harbor', target: 1 }],
  ['bakeryPostcard', { special: 'postcards', dest: 'bakery', target: 1 }],
  ['nightSkyPostcard', { special: 'postcards', dest: 'nightSky', target: 1 }],
  ['frequentFlyer', { special: 'vacationTrips', target: 3 }],
  ['penPal', { special: 'postcards', target: 10 }],
  ['parkFirstVisit', { special: 'park', key: 'visits', target: 1 }],
  ['loopStar', { special: 'park', key: 'coasterRides', target: 1 }],
  ['handsUp', { special: 'park', key: 'coasterRides', target: 3 }],
  ['candyDay', { special: 'park', key: 'candyBought', target: 3 }],
  ['nightLights', { special: 'park', key: 'nightVisit', target: 1 }],
  ['parkExplorer', { special: 'park', key: 'visits', target: 5 }],
  ['lanternKeeper', { special: 'gameBest', game: 'lanternFloat', target: 60 }],
  ['snailCourier', { special: 'gameBest', game: 'snailMail', target: 60 }],
  ['ghostWhisperer', { counter: 'ghostsCaught', target: 25 }],
  ['harborMaster', { counter: 'cratesShipped', target: 50 }],
  ['rocketHero', { counter: 'rescues', target: 15 }],
  ['pipeDreamer', { special: 'gameBest', game: 'pipeFlow', target: 70 }],
  ['weekStreak', { special: 'streak', target: 7 }],
  ['medsMaster', { counter: 'medsGiven', target: 10 }],
  ['marketDay', { counter: 'sells', target: 25 }],
  ['memoryKeeper', { counter: 'galleryPhotos', target: 40 }],
  ['interiorDesigner', { special: 'decorPlaced', target: 20 }],
  ['storyTeller', { counter: 'recapsSeen', target: 3 }],
  ['teaTime', { special: 'gameBest', game: 'teaParty', target: 60 }],
  ['pancakeMountain', { special: 'gameBest', game: 'pancakeTower', target: 40 }],
  ['burgerBoss', { special: 'gameBest', game: 'burgerBuild', target: 60 }],
  ['veggieChef', { special: 'gameBest', game: 'veggieChop', target: 70 }],
  ['cakeParade', { counter: 'cakesServed', target: 25 }],
  ['nougatFlood', { counter: 'nougatGlobs', target: 10 }],
  ['bestBuddies', { special: 'playtimeMin', target: 300 }],
  ['inseparable', { special: 'playtimeMin', target: 1500 }],
  ['tickleTornado', { counter: 'tickles', target: 200 }],
  ['monthStreak', { special: 'streak', target: 30 }],
  ['hatParade', { special: 'outfitsOwned', target: 10 }],
  ['bigSpender', { special: 'coinsSpent', target: 3000 }],
  // V4/G53 (PLAN4 §C-SYS5.4/§B6): the secret BONUS sticker — outside the
  // regular count (secret: true), unlocked only via the 'herzGooby' code
  // word, LAST in table order.
  ['herzGooby', { code: 'herzGooby' }],
];

/** V6/F1: the six themed-page ids in page order (pages 9–14). */
const V6_PAGE_IDS = ['travel', 'funkelpark', 'arcadeStars', 'cozyLife', 'foodieFeast', 'bestFriends'];

// ------------------------------------------------------------------ catalog

test('84 regular stickers + secret, ids in frozen table order, unique', () => {
  // V6/F1: 28 §C5.1 originals + 20 V5 wave-1 + 36 V6 themed = 84 regular;
  // the secret herzGooby stays outside the count and LAST in table order.
  assert.equal(STICKERS.length, 85);
  assert.equal(TOTAL_BOOK_STICKERS, 84);
  assert.deepEqual(STICKERS.map((s) => s.id), SPEC_CONDS.map(([id]) => id));
  assert.equal(new Set(STICKERS.map((s) => s.id)).size, 85);
  assert.equal(getSticker('firstNom'), STICKERS[0]);
  assert.equal(getSticker('bogus'), undefined);
  // the ONE secret def is herzGooby, flagged + last in table order
  assert.deepEqual(STICKERS.filter((s) => s.secret).map((s) => s.id), ['herzGooby']);
  assert.equal(STICKERS[84].id, 'herzGooby');
  // the 28 §C5.1 originals + 20 V5 rows stay FROZEN in their exact positions
  assert.equal(STICKERS[27].id, 'albumMaster');
  assert.equal(STICKERS[28].id, 'snackStack');
  assert.equal(STICKERS[47].id, 'codeWhisperer');
  // the V6/F1 append starts right after the frozen 48
  assert.equal(STICKERS[48].id, 'beachPostcard');
  assert.equal(STICKERS[83].id, 'bigSpender');
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

test('page layout: 14 pages of 6 (V6/F1), table order preserved', () => {
  assert.deepEqual([...STICKER_PAGE_SIZES], Array(14).fill(6));
  const pages = stickerPages();
  assert.deepEqual(pages.map((p) => p.length), Array(14).fill(6));
  // V4/G53 (§C-SYS5.4): pages carry the 84 REGULAR defs only — the secret
  // slot is appended to the LAST page by ui/albumScreen.js, outside paging.
  assert.deepEqual(
    pages.flat().map((s) => s.id),
    STICKERS.filter((s) => !s.secret).map((s) => s.id)
  );
  assert.ok(pages.flat().every((s) => s.id !== 'herzGooby'));
});

test('V6/F1 STICKER_PAGES: positional catalog (ids/titles/icons/tints) matches the slicing', () => {
  // one presentation row per page, positional with stickerPages()
  assert.equal(STICKER_PAGES.length, STICKER_PAGE_SIZES.length);
  assert.deepEqual(STICKER_PAGES.slice(8).map((p) => p.id), V6_PAGE_IDS);
  const pages = stickerPages();
  STICKER_PAGES.forEach((meta, i) => {
    assert.ok(Object.isFrozen(meta), `${meta.id} frozen`);
    assert.match(meta.tint, /^#[0-9A-Fa-f]{6}$/, `${meta.id} tint is #rrggbb`);
    assert.ok(typeof meta.icon === 'string' && meta.icon.length > 0, `${meta.id} icon`);
    if (i < 8) {
      // legacy pages: numbered titles (titleKey null), rows carry no page id
      assert.equal(meta.id, `classic${i + 1}`);
      assert.equal(meta.titleKey, null);
      assert.ok(pages[i].every((d) => d.page === undefined), `page ${i} legacy rows`);
    } else {
      // themed pages: EN+DE titles + every row pinned to its page id
      assert.equal(meta.titleKey, `stickerbook.pageTitle.${meta.id}`);
      assert.equal(typeof EN[meta.titleKey], 'string', `EN ${meta.titleKey}`);
      assert.equal(typeof DE[meta.titleKey], 'string', `DE ${meta.titleKey}`);
      assert.ok(pages[i].every((d) => d.page === meta.id), `page ${i} rows carry page='${meta.id}'`);
    }
  });
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
/** V6/F1: a synthetic (valid-shaped) postcard-archive entry. */
function card(destId, i) {
  return { destId, dayIndex: 1, variant: 1, atMs: 1000 + i };
}

function maxedState() {
  const s = defaultState();
  s.level = 40;
  s.weight.value = 86;
  Object.assign(s.achievements.counters, {
    // originals raised where a V5 sticker shares the counter (higher target
    // still satisfies the lower original — e.g. feeds 50 covers firstNom 1)
    feeds: 50, washes: 25, balls: 50, sleeps: 25, sickEver: 1, vetTrips: 1,
    harvests: 25, photosTaken: 10, trips: 10, holeInOnes: 1, deliveries: 50,
    perfectCakes: 1, surfRuns: 1,
    // V5/STICKERS wave-1 counters (all existing §B1/§B2 keys); tickles and
    // nougatGlobs raised for the V6 rows (200 covers bellyLaugh's 50,
    // 10 covers nutellaGlob's 1)
    tickles: 200, waterings: 50, plantings: 10, cleanTrips: 5,
    modifierPlays: 5, questsDone: 10, cures: 3, radioMinutes: 30,
    codesRedeemed: 1, nougatGlobs: 10,
    // V6/F1 counter rows (all existing §B1/§B2 save-schema keys)
    ghostsCaught: 25, cratesShipped: 50, rescues: 15, medsGiven: 10,
    sells: 25, galleryPhotos: 40, recapsSeen: 3, cakesServed: 25,
  });
  s.minigames.best.danceParty = 100;
  // V5/STICKERS gameBest rows
  s.minigames.best.carrotCatch = 60;
  s.minigames.best.memoryMatch = 40;
  s.minigames.best.goobySays = 100;
  // V6/F1 gameBest rows
  s.minigames.best.lanternFloat = 60;
  s.minigames.best.snailMail = 60;
  s.minigames.best.pipeFlow = 70;
  s.minigames.best.teaParty = 60;
  s.minigames.best.pancakeTower = 40;
  s.minigames.best.burgerBuild = 60;
  s.minigames.best.veggieChop = 70;
  s.collections.entries['fish.goldenFish'] = 1;
  s.collections.claimedSets = { veggies: 1, fish: 1, landmarks: 1, treats: 1 };
  s.skins.owned = ['cream', 'snow'];
  s.outfits.equipped = { hat: 'crown', glasses: 'starGlasses', neck: 'scarfRed', back: null };
  s.codes.redeemed.herzGooby = 777; // V4/G53: secret unlocks via its code latch
  // ── V6/F1 slices (pure-read specials) ──
  // 10 postcards spanning all four destination rows (penPal needs 10 total)
  s.vacation = {
    trips: 3, // frequentFlyer
    archive: [
      card('beach', 0), card('harbor', 1), card('bakery', 2), card('nightSky', 3),
      card('beach', 4), card('harbor', 5), card('bakery', 6), card('nightSky', 7),
      card('beach', 8), card('nightSky', 9),
    ],
  };
  s.themePark = { visits: 5, nightVisit: true, rides: { coaster: 3 }, candyBought: 3 };
  s.daily.streak = 30; // weekStreak 7 + monthStreak 30
  s.profile.playtimeMin = 1500; // bestBuddies 300 + inseparable 1500
  s.profile.coinsSpent = 3000; // bigSpender
  s.outfits.owned = Array.from({ length: 10 }, (_, i) => `piece${i}`); // hatParade
  // interiorDesigner: the default save ships 1 non-default piece (radio) —
  // 19 more placed non-defaults reach the 20 target
  for (let i = 0; i < 19; i += 1) s.furniture.placed[`living:v6spec${i}`] = `fancy${i}`;
  return s;
}

test('all 80 counter/special stickers unlock through applyStickerUnlocks', () => {
  const eventIds = SPEC_CONDS.filter(([, c]) => c.event).map(([id]) => id);
  assert.deepEqual(eventIds, ['grumpMorning', 'rainyDay', 'starGazer', 'towTrouble']);
  const { state, unlocked } = applyStickerUnlocks(maxedState(), 777);
  // 80 counter/special (24 original + 20 V5 + 36 V6) + the code-latched
  // secret = 81
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
    // ── V6/F1 pure-read specials ──
    else if (cond.special === 'postcards') {
      // per-destination rows: a card from a DIFFERENT destination never
      // counts; total rows: one short of the target
      below.vacation = {
        archive: cond.dest
          ? [card(cond.dest === 'beach' ? 'harbor' : 'beach', 0)]
          : Array.from({ length: cond.target - 1 }, (_, i) => card('beach', i)),
      };
    } else if (cond.special === 'vacationTrips') below.vacation = { trips: cond.target - 1 };
    else if (cond.special === 'park') {
      below.themePark = { visits: 0, nightVisit: false, rides: { coaster: 0 }, candyBought: 0 };
      if (cond.key === 'visits') below.themePark.visits = cond.target - 1;
      else if (cond.key === 'coasterRides') below.themePark.rides.coaster = cond.target - 1;
      else if (cond.key === 'candyBought') below.themePark.candyBought = cond.target - 1;
      // nightVisit: the un-latched flag IS below threshold
    } else if (cond.special === 'streak') below.daily.streak = cond.target - 1;
    else if (cond.special === 'playtimeMin') below.profile.playtimeMin = cond.target - 1;
    else if (cond.special === 'coinsSpent') below.profile.coinsSpent = cond.target - 1;
    else if (cond.special === 'outfitsOwned') {
      below.outfits.owned = Array.from({ length: cond.target - 1 }, (_, i) => `piece${i}`);
    } else if (cond.special === 'decorPlaced') {
      // default save ships 1 non-default piece (radio) → add target-2 more
      for (let i = 0; i < cond.target - 2; i += 1) below.furniture.placed[`living:x${i}`] = `b${i}`;
    }
    assert.equal(isStickerSatisfied(def, below), false, `${id} below threshold`);
    assert.equal(isStickerSatisfied(def, at), true, `${id} at threshold`);
    const p = stickerProgress(def, at);
    assert.equal(p.current, p.target, `${id} progress caps at target`);
  }
});
