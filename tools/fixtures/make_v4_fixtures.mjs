#!/usr/bin/env node
// GODOT W1/STATE — v4 fixture + golden-value generator.
//
// Imports the REAL web code from /workspace/GOOBY (read-only reference) and
// produces:
//   GOOBY-GODOT/tests/fixtures/v4_fresh.json        — pristine defaultState()
//   GOOBY-GODOT/tests/fixtures/v4_midgame.json      — level 12, stickers,
//     furniture placed, garden planted, ACTIVE vacation, counters, …
//   GOOBY-GODOT/tests/fixtures/v4_maxed.json        — level 40, everything owned
//   GOOBY-GODOT/tests/fixtures/v2_legacy.json       — v2-shaped legacy save
//   GOOBY-GODOT/tests/fixtures/v2_legacy.expected_v4.json — what the WEB
//     migration chain (save.js load()) turns the v2 save into (parity target
//     for migration_v4.gd's ported v0→v4 chain)
//   GOOBY-GODOT/tests/fixtures/golden_values.json   — reference numbers
//     computed BY THE WEB CODE (leveling/stats/economy/sleep/offline) that the
//     GDScript ports must reproduce exactly ("Zahlengleichheit").
//
// Every fixture is round-tripped through the web save pipeline
// (persist() → load() → migrations + validate()) so the JSON on disk is a
// REAL v4 save exactly as the web app would have written it.
//
// Determinism: the clock is pinned via core/clock.js configure(); TZ is
// forced to UTC so localDay() matches the GDScript port's UTC day math.

process.env.TZ = 'UTC';

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const GOOBY = join(HERE, '..', '..', 'GOOBY');
const OUT = join(HERE, '..', '..', 'GOOBY-GODOT', 'tests', 'fixtures');
mkdirSync(OUT, { recursive: true });

const clock = await import(join(GOOBY, 'src/core/clock.js'));
const save = await import(join(GOOBY, 'src/core/save.js'));
const storeMod = await import(join(GOOBY, 'src/core/store.js'));
const stats = await import(join(GOOBY, 'src/systems/stats.js'));
const leveling = await import(join(GOOBY, 'src/systems/leveling.js'));
const economy = await import(join(GOOBY, 'src/systems/economy.js'));
const sleep = await import(join(GOOBY, 'src/systems/sleep.js'));
const offline = await import(join(GOOBY, 'src/systems/offline.js'));
const vacation = await import(join(GOOBY, 'src/systems/vacation.js'));
const constants = await import(join(GOOBY, 'src/data/constants.js'));
const stickers = await import(join(GOOBY, 'src/data/stickers.js'));
const outfits = await import(join(GOOBY, 'src/data/outfits.js'));
const furniture = await import(join(GOOBY, 'src/data/furniture.js'));
const achievements = await import(join(GOOBY, 'src/data/achievements.js'));
const vacations = await import(join(GOOBY, 'src/data/vacations.js'));

// Give save.js's lazy dynamic import of systems/recap.js a beat to resolve so
// the recap baseline in the migration parity fixture is the canonical one.
await new Promise((r) => setTimeout(r, 50));

/** Pinned "now" for all fixtures: 2026-01-15T12:00:00Z. */
const NOW_MS = Date.UTC(2026, 0, 15, 12, 0, 0);
const DAY = 86400000;

/** Round-trip a raw state through the REAL web pipeline (migrate+validate). */
function webValidate(raw) {
  save.clear();
  save.persist(raw);
  const res = save.load();
  save.clear();
  if (res.fresh || res.recovered) {
    throw new Error('fixture rejected by web load(): ' + JSON.stringify(res));
  }
  return res.state;
}

function writeJson(name, data) {
  const path = join(OUT, name);
  writeFileSync(path, JSON.stringify(data, null, 1) + '\n');
  console.log('wrote', path, JSON.stringify(data).length, 'bytes');
}

// ── fixture 1: fresh ────────────────────────────────────────────────────────
clock.configure({ now: NOW_MS });
const fresh = webValidate(save.defaultState());
writeJson('v4_fresh.json', fresh);

// ── fixture 2: midgame (level 12, active vacation, planted garden, …) ──────
const CREATED_MS = NOW_MS - 60 * DAY;
clock.configure({ now: CREATED_MS });
const mid = save.defaultState();
clock.configure({ now: NOW_MS });

mid.lastTickAt = NOW_MS - 2 * 3600000; // app closed 2 h ago
mid.stats = { hunger: 62, energy: 55, hygiene: 71, fun: 48 };
mid.coins = 4210;
mid.level = 12;
mid.xp = 310;
mid.inventory = { carrot: 5, apple: 2, burger: 1, cake: 1 };
mid.items = { medicine: 1, fertilizer: 2, 'seed:carrot': 3, 'harvested:carrot': 2 };
// 20 real sticker ids, unlocked over the last weeks
for (const [i, st] of stickers.STICKERS.slice(0, 20).entries()) {
  mid.stickers.unlocked[st.id] = NOW_MS - (20 - i) * DAY;
  mid.stickers.seen[st.id] = true;
}
// furniture: 8 real catalog ids owned, 3 placed in slots (slot system!)
const FURN_IDS = furniture.FURNITURE.slice(0, 8).map((f) => f.id);
mid.furniture.owned = [...new Set(['radio', ...FURN_IDS])];
const livingSlots = furniture.roomSlots('living'); // ['sofa', 'tv', 'rug', …]
mid.furniture.placed = {
  'living:shelf1': 'radio',
  [`living:${livingSlots[0]}`]: FURN_IDS[0],
  [`living:${livingSlots[1]}`]: FURN_IDS[3],
};
mid.decor.wallpaper = { living: furniture.WALLPAPER_IDS[1] ?? 'cream' };
mid.decor.floor = { living: furniture.FLOOR_IDS[1] ?? 'wood' };
// outfits: 8 owned, hat equipped; skins: caramel equipped
const OUTFIT_IDS = outfits.OUTFITS.slice(0, 8).map((o) => o.id);
mid.outfits.owned = OUTFIT_IDS;
mid.outfits.equipped = { hat: OUTFIT_IDS[0], glasses: null, neck: null, back: null };
mid.skins = { owned: ['cream', 'caramel'], equipped: 'caramel' };
// garden: 5 plots owned, 2 planted (one mid-growth watered, one ready-ish)
mid.garden.plotsOwned = 5;
mid.garden.lastTickAt = NOW_MS - 2 * 3600000;
mid.garden.plots[0] = {
  crop: 'carrot', plantedAt: NOW_MS - 30 * 60000, progressMin: 8,
  wateredUntil: NOW_MS + 10 * 60000, waterings: 1, fertilized: false,
};
mid.garden.plots[1] = {
  crop: 'pumpkin', plantedAt: NOW_MS - 5 * 3600000, progressMin: 220,
  wateredUntil: 0, waterings: 2, fertilized: true,
};
// minigames history
mid.minigames.best = { carrotCatch: 66, bunnyHop: 21, memoryMatch: 40 };
mid.minigames.plays = { carrotCatch: 31, bunnyHop: 12, memoryMatch: 5 };
mid.minigames.lastPlayDay = { carrotCatch: '2026-01-14' };
mid.minigames.difficulty = { carrotCatch: 'hard' };
mid.minigames.beaten = { carrotCatch: { normal: true } };
mid.minigames.bestByDiff = { carrotCatch: { hard: 51 } };
mid.minigames.endlessBest = { bunnyHop: 14 };
// achievements: 6 real ids + counters
for (const a of achievements.ACHIEVEMENTS.slice(0, 6)) {
  mid.achievements.unlocked[a.id] = NOW_MS - 9 * DAY;
}
Object.assign(mid.achievements.counters, {
  feeds: 152, washes: 38, sleeps: 41, trips: 12, tickles: 77,
  harvests: 23, plantings: 30, waterings: 84, questsDone: 19, deliveries: 7,
});
mid.daily = { lastClaimDay: '2026-01-15', streak: 5 };
mid.quests = {
  day: '2026-01-15',
  active: [{ id: 'q.feed3', category: 'care', event: 'feed', target: 3, progress: 1, claimed: false }],
  rerolledDay: '', completedTotal: 19,
};
mid.collections = { entries: { sunnyCarp: 2, radish: 4 }, claimedSets: {} };
mid.health = { state: 'queasy', junkScore: 55, neglectMin: 0, recoverMin: 10, since: NOW_MS - 3600000 };
mid.weight = { value: 62 };
mid.profile = { playtimeMin: 2410, coinsEarned: 9800, coinsSpent: 5590, distanceM: 10400, photos: 3 };
mid.gallery = { count: 3, lastAddedAt: NOW_MS - 4 * DAY, hintShown: true };
mid.nougat = { lastGlobAt: NOW_MS - 2 * DAY, installed: true };
mid.radio = {
  ...mid.radio, station: 'gooby-fm', playing: true, shuffle: false,
  trims: { 'track-01': { vol: 60, on: true } },
};
mid.codes = { redeemed: { UpdateLiebe: NOW_MS - 20 * DAY }, lockUntil: 0, buffs: { doubleCoinsUntil: 0 } };
mid.recap.lastRecapLevel = 10;
mid.recap.history = [{ level: 10, at: NOW_MS - 12 * DAY, stats: { feeds: 100 } }];
mid.settings = {
  ...mid.settings, lang: 'de', sfx: false, music: true, uiScale: 115,
  volumes: { master: 70, sfx: 100, music: 55, voice: 100, ambience: 80 },
  devUnlocked: true,
};
mid.onboarding = { done: true, step: 99, whatsNew2Seen: true, whatsNew3Seen: true, whatsNew4Seen: true };
// ACTIVE vacation: booked 1 day ago to the beach → still AWAY, 1 postcard due
mid.vacation = vacation.bookSlice(null, vacations.VACATION_IDS[0], NOW_MS - DAY);
{
  const t = vacation.tick({ vacation: mid.vacation }, NOW_MS);
  if (t.changes) mid.vacation = t.changes;
}
mid.themePark = { visits: 4, nightVisit: true, rides: { coaster: 6, wheel: 3 }, handsUp: 2, candyBought: 5 };
const midgame = webValidate(mid);
writeJson('v4_midgame.json', midgame);

// ── fixture 3: maxed ────────────────────────────────────────────────────────
clock.configure({ now: CREATED_MS });
const max = save.defaultState();
clock.configure({ now: NOW_MS });
max.lastTickAt = NOW_MS;
max.stats = { hunger: 100, energy: 100, hygiene: 100, fun: 100 };
max.coins = 99999;
max.level = 40;
max.xp = 0;
for (const st of stickers.STICKERS) {
  max.stickers.unlocked[st.id] = NOW_MS - 30 * DAY;
  max.stickers.seen[st.id] = true;
}
max.furniture.owned = [...new Set(['radio', ...furniture.FURNITURE.map((f) => f.id)])];
max.outfits.owned = outfits.OUTFITS.map((o) => o.id);
max.outfits.equipped = {
  hat: max.outfits.owned[0], glasses: null, neck: null, back: null,
};
max.skins = { owned: ['cream', 'snow', 'caramel', 'ash', 'rose', 'midnight', 'golden'], equipped: 'golden' };
max.garden.plotsOwned = 6;
for (const a of achievements.ACHIEVEMENTS) max.achievements.unlocked[a.id] = NOW_MS - 40 * DAY;
Object.assign(max.achievements.counters, { feeds: 2000, washes: 800, sleeps: 500, waterings: 1500 });
max.quickDelivery = true;
max.profile = { playtimeMin: 30000, coinsEarned: 250000, coinsSpent: 150000, distanceM: 99000, photos: 40 };
max.gallery = { count: 40, lastAddedAt: NOW_MS - DAY, hintShown: true };
max.vacation = (() => {
  let v = vacation.pickupSlice(vacation.bookSlice(null, vacations.VACATION_IDS[0], NOW_MS - 40 * DAY));
  for (const id of vacations.VACATION_IDS) v.visited[id] = true;
  v.trips = 12;
  v.postcards = 8;
  return v;
})();
max.themePark = { visits: 30, nightVisit: true, rides: { coaster: 50, wheel: 40 }, handsUp: 20, candyBought: 60 };
max.onboarding = { done: true, step: 99, whatsNew2Seen: true, whatsNew3Seen: true, whatsNew4Seen: true };
const maxed = webValidate(max);
writeJson('v4_maxed.json', maxed);

// ── fixture 4: v2 legacy save + web-expected v4 (chain parity target) ──────
clock.configure({ now: NOW_MS });
const v2 = {
  v: 2,
  createdAt: CREATED_MS,
  lastTickAt: NOW_MS - 5 * 3600000,
  stats: { hunger: 40, energy: 80, hygiene: 30, fun: 66 },
  sleep: { sleeping: false, startedAt: 0, wakeAt: 0 },
  grumpyUntil: 0,
  coins: 812,
  xp: 40,
  level: 7,
  inventory: { carrot: 1 },
  furniture: { owned: ['bedDouble'], placed: { 'bedroom:bed': 'bedDouble' } },
  decor: { wallpaper: {}, floor: {} },
  outfits: { owned: ['partyHat'], equipped: { hat: 'partyHat', glasses: null, neck: null } },
  minigames: { best: { carrotCatch: 33 }, plays: { carrotCatch: 9 }, lastPlayDay: {} },
  achievements: {
    unlocked: { firstNom: NOW_MS - 50 * DAY },
    counters: {
      feeds: 60, washes: 10, sleeps: 12, trips: 2, tickles: 5, petsToday: 0, petsDay: '',
      harvests: 3, plantings: 4, waterings: 9, sells: 1, cures: 0, vetTrips: 0,
      deliveries: 0, questsDone: 2, photosTaken: 0, nightPlays: 0, medsGiven: 0, balls: 7,
    },
  },
  daily: { lastClaimDay: '2026-01-10', streak: 2 },
  quickDelivery: false,
  settings: { lang: 'de', sfx: true, music: false, haptics: true, notifications: 'unasked' },
  onboarding: { done: true, step: 99, whatsNew2Seen: false },
  garden: {
    plotsOwned: 4,
    plots: [
      { crop: 'radish', plantedAt: NOW_MS - 3600000, progressMin: 5, wateredUntil: 0, waterings: 1, fertilized: false },
      { crop: null, plantedAt: 0, progressMin: 0, wateredUntil: 0, waterings: 0, fertilized: false },
      { crop: null, plantedAt: 0, progressMin: 0, wateredUntil: 0, waterings: 0, fertilized: false },
      { crop: null, plantedAt: 0, progressMin: 0, wateredUntil: 0, waterings: 0, fertilized: false },
      { crop: null, plantedAt: 0, progressMin: 0, wateredUntil: 0, waterings: 0, fertilized: false },
      { crop: null, plantedAt: 0, progressMin: 0, wateredUntil: 0, waterings: 0, fertilized: false },
    ],
    lastTickAt: NOW_MS - 3600000,
  },
  health: { state: 'healthy', junkScore: 10, neglectMin: 0, recoverMin: 0, since: 0 },
  weight: { value: 48 },
  quests: { day: '', active: [], rerolledDay: '', completedTotal: 2 },
  collections: { entries: {}, claimedSets: {} },
  skins: { owned: ['cream'], equipped: 'cream' },
  items: { medicine: 0, fertilizer: 1 },
  profile: { playtimeMin: 300, coinsEarned: 1500, coinsSpent: 688, distanceM: 900, photos: 0 },
};
writeJson('v2_legacy.json', v2);
const v2expected = webValidate(v2);
writeJson('v2_legacy.expected_v4.json', v2expected);

// ── fixture 5: extras — additive slices real saves carry (E2-P1/P2-3) ──────
// cutscenes.seen / care.toiletAt+sickNotifyAt / minigames.difficulty plus the
// additive counters (sickEver/holeInOnes/photoXp*) and a CHEATER themePark
// (web validate() clamps NONE of these — they must survive to disk verbatim,
// so the Godot migration is forced to map or honestly report them).
// NOTE deliberately generated AFTER fixture 4: clock.js runs on real wall
// time, and an extra save.load() here would drift the recap baseline stamp
// in v2_legacy.expected_v4.json by ~1 ms.
clock.configure({ now: CREATED_MS });
const extras = save.defaultState();
clock.configure({ now: NOW_MS });
extras.coins = 1234;
extras.level = 9;
extras.minigames.difficulty = { carrotCatch: 'easy', bunnyHop: 'hard' };
extras.minigames.best = { carrotCatch: 44 };
extras.cutscenes = { seen: { vacDeparture: true, versaryMonth: true } };
extras.care = { toiletAt: NOW_MS - 3600000, sickNotifyAt: NOW_MS - 2 * 3600000 };
Object.assign(extras.achievements.counters, {
  sickEver: 2, holeInOnes: 3, photoXpDay: '2026-01-15', photoXpToday: 2,
});
extras.themePark = {
  visits: 1e15, nightVisit: 'ja',
  rides: { coaster: -5, ufo: 9 }, handsUp: 1e15, candyBought: 12,
};
extras.onboarding = { done: true, step: 99, whatsNew2Seen: true, whatsNew3Seen: true, whatsNew4Seen: true };
const extrasFixture = webValidate(extras);
writeJson('v4_extras.json', extrasFixture);

// ── golden values: computed BY the web systems modules ──────────────────────
clock.configure({ now: NOW_MS });
const golden = { generatedAt: NOW_MS, tz: 'UTC' };

// leveling
golden.leveling = {
  maxLevel: constants.LEVELING.MAX_LEVEL,
  xpToNext: Object.fromEntries(
    Array.from({ length: 40 }, (_, i) => [i + 1, leveling.xpToNext(i + 1)])
  ),
  cumulativeXpTo40: leveling.cumulativeXpToLevel(40),
  cumulativeXpTo10: leveling.cumulativeXpToLevel(10),
  applyXpCases: [
    { progress: { xp: 0, level: 1 }, amount: 100 },
    { progress: { xp: 90, level: 1 }, amount: 5 },
    { progress: { xp: 0, level: 1 }, amount: 1000 },
    { progress: { xp: 310, level: 12 }, amount: 650 },
    { progress: { xp: 0, level: 39 }, amount: 3000 },
    { progress: { xp: 0, level: 40 }, amount: 500 },
    { progress: { xp: 0, level: 12 }, amount: 0 },
  ].map((c) => ({ ...c, result: leveling.applyXp({ ...c.progress }, c.amount) })),
  minigameXp: Object.fromEntries(
    [0, 4, 10, 25, 26, 29, 30, 31, 50, 100].map((c) => [c, leveling.minigameXp(c)])
  ),
};

// stats
golden.stats = {
  ratesAwake: constants.STATS.RATES_AWAKE,
  ratesAsleep: constants.STATS.RATES_ASLEEP,
  applyTickCases: [
    { stats: { hunger: 80, energy: 90, hygiene: 85, fun: 70 }, dtMin: 10, opts: {} },
    { stats: { hunger: 80, energy: 90, hygiene: 85, fun: 70 }, dtMin: 10, opts: { asleep: true } },
    { stats: { hunger: 50, energy: 10, hygiene: 50, fun: 50 }, dtMin: 30, opts: { asleep: true } },
    { stats: { hunger: 30, energy: 40, hygiene: 20, fun: 25 }, dtMin: 480, opts: { rateMult: 0.3 } },
    { stats: { hunger: 1, energy: 1, hygiene: 1, fun: 1 }, dtMin: 100, opts: {} },
  ].map((c) => ({ ...c, result: stats.applyTick(c.stats, c.dtMin, c.opts) })),
  moodCases: [
    { stats: { hunger: 80, energy: 90, hygiene: 85, fun: 70 }, opts: {} },
    { stats: { hunger: 100, energy: 100, hygiene: 100, fun: 100 }, opts: {} },
    { stats: { hunger: 20, energy: 90, hygiene: 85, fun: 70 }, opts: {} },
    { stats: { hunger: 80, energy: 10, hygiene: 85, fun: 70 }, opts: {} },
    { stats: { hunger: 80, energy: 90, hygiene: 85, fun: 70 }, opts: { debuff: 15 } },
    { stats: { hunger: 0, energy: 0, hygiene: 0, fun: 0 }, opts: {} },
  ].map((c) => ({ ...c, result: stats.mood(c.stats, c.opts), band: stats.moodBand(stats.mood(c.stats, c.opts)) })),
  bands: constants.MOOD.BANDS,
};

// economy: quickPrice + award/spend + day-cap ledgers, run on a REAL store
golden.economy = (() => {
  const quickPrices = Object.fromEntries(
    [5, 6, 10, 12, 14, 16, 25, 30, 40, 400].map((p) => [p, economy.quickPrice(p)])
  );
  clock.configure({ now: NOW_MS });
  const state = save.defaultState();
  const store = storeMod.createStore(state, { autosave: false });
  const steps = [];
  const step = (kind, args, ret) =>
    steps.push({
      kind, args, ret,
      coins: state.coins,
      coinsEarned: state.profile.coinsEarned,
      coinsSpent: state.profile.coinsSpent,
      dayCoins: state.modifiers.dayCoins,
      endlessCoins: state.modifiers.endlessCoins ?? 0,
    });
  step('start', null, null);
  step('award', [120, 'minigame'], economy.award(store, 120, 'minigame'));
  step('award', [100, 'glueckspilz'], economy.award(store, 100, 'glueckspilz'));
  step('award', [100, 'modifier'], economy.award(store, 100, 'modifier'));
  step('award', [40, 'glueckspilz'], economy.award(store, 40, 'glueckspilz'));
  step('award', [60, 'endless'], economy.award(store, 60, 'endless'));
  step('award', [60, 'endless'], economy.award(store, 60, 'endless'));
  step('award', [60, 'endless'], economy.award(store, 60, 'endless'));
  step('spend', [100, 'shop'], economy.spend(store, 100, 'shop'));
  step('spend', [999999, 'shop'], economy.spend(store, 999999, 'shop'));
  step('award', [7.9, 'daily'], economy.award(store, 7.9, 'daily'));
  step('spend', [7.1, 'shop'], economy.spend(store, 7.1, 'shop'));
  return {
    startingCoins: constants.ECONOMY.STARTING_COINS,
    dayCoinCap: constants.MODIFIER.DAY_COIN_CAP,
    quickPrices,
    steps,
  };
})();

// sleep
golden.sleep = {
  durations: Object.fromEntries(
    [0, 10, 50, 65, 69, 69.9, 90, 100].map((e) => [e, sleep.sleepDurationMin(e)])
  ),
  canSleepCases: [
    { energy: 69.9, sleeping: false }, { energy: 70, sleeping: false }, { energy: 10, sleeping: true },
  ].map((c) => ({
    ...c,
    result: sleep.canSleep({ sleep: { sleeping: c.sleeping }, stats: { energy: c.energy } }),
  })),
  completedGrants: (() => {
    const s = {
      xp: 95, level: 3, coins: 10,
      achievements: { counters: { sleeps: 4 } },
    };
    const out = sleep.applyCompletedSleepGrants(s);
    return { input: { xp: 95, level: 3, coins: 10, sleeps: 4 }, output: out };
  })(),
  tickSleepCase: (() => {
    // energy 40 → duration 18 min; tick 20 min later → auto-wake + grants
    const start = sleep.startSleep(
      { stats: { hunger: 60, energy: 40, hygiene: 60, fun: 60 }, sleep: {}, xp: 0, level: 1, coins: 0, lastTickAt: NOW_MS, achievements: { counters: { sleeps: 0 } } },
      NOW_MS
    );
    const res = sleep.tickSleep(start, NOW_MS + 20 * 60000);
    return { started: start.sleep, result: res };
  })(),
};

// offline: core paths (stats decay / sleep completion / statLow / vacation
// freeze). Compared fields: stats, lastTickAt, sleep, xp/level/coins, events
// (minus the engine events the W1 port deliberately skips: health/garden).
function offlineCase(label, mutate) {
  clock.configure({ now: NOW_MS });
  const st = save.defaultState();
  st.createdAt = CREATED_MS;
  mutate(st);
  const res = offline.simulateOffline(st, NOW_MS);
  return {
    label,
    input: {
      stats: st.stats, lastTickAt: st.lastTickAt, sleep: st.sleep,
      xp: st.xp, level: st.level, coins: st.coins,
      vacation: st.vacation ?? null,
    },
    result: {
      stats: res.state.stats, lastTickAt: res.state.lastTickAt,
      sleep: res.state.sleep, xp: res.state.xp, level: res.state.level,
      coins: res.state.coins,
      vacationPhase: res.state.vacation?.phase ?? 'none',
      vacationPostcards: res.state.vacation?.postcards ?? 0,
      events: res.events.filter((e) =>
        e === 'wokeUp' || e.startsWith('statLow:') || e.startsWith('vacation')),
    },
  };
}
golden.offline = {
  awakeRateMult: constants.OFFLINE.AWAKE_RATE_MULT,
  awakeCapMin: constants.OFFLINE.AWAKE_CAP_MIN,
  cases: [
    offlineCase('short_awake_2h', (st) => {
      st.stats = { hunger: 62, energy: 55, hygiene: 71, fun: 48 };
      st.lastTickAt = NOW_MS - 2 * 3600000;
    }),
    offlineCase('long_awake_20h_capped', (st) => {
      st.stats = { hunger: 90, energy: 90, hygiene: 90, fun: 90 };
      st.lastTickAt = NOW_MS - 20 * 3600000;
    }),
    offlineCase('statlow_crossings', (st) => {
      st.stats = { hunger: 30, energy: 90, hygiene: 26, fun: 27 };
      st.lastTickAt = NOW_MS - 3 * 3600000;
    }),
    offlineCase('sleep_completes_offline', (st) => {
      st.stats = { hunger: 70, energy: 20, hygiene: 70, fun: 70 };
      st.sleep = { sleeping: true, startedAt: NOW_MS - 60 * 60000, wakeAt: NOW_MS - 36 * 60000 };
      st.lastTickAt = NOW_MS - 60 * 60000;
    }),
    offlineCase('still_asleep', (st) => {
      st.stats = { hunger: 70, energy: 50, hygiene: 70, fun: 70 };
      st.sleep = { sleeping: true, startedAt: NOW_MS - 5 * 60000, wakeAt: NOW_MS + 10 * 60000 };
      st.lastTickAt = NOW_MS - 5 * 60000;
    }),
    offlineCase('vacation_freeze_and_catchup', (st) => {
      st.stats = { hunger: 80, energy: 80, hygiene: 80, fun: 80 };
      st.lastTickAt = NOW_MS - 2 * DAY;
      st.vacation = vacation.bookSlice(null, vacations.VACATION_IDS[0], NOW_MS - 2 * DAY);
    }),
  ],
};

// vacation math the migration keeps (remaining-time proof for the tests)
golden.vacation = {
  ids: vacations.VACATION_IDS,
  msPerDay: vacation.VACATION.MS_PER_DAY,
  pickupWindowMs: vacation.VACATION.PICKUP_WINDOW_MS,
  midgameRemainingMs: vacation.remainingMs({ vacation: midgame.vacation }, NOW_MS),
  midgamePhase: midgame.vacation.phase,
  nowMs: NOW_MS,
};

writeJson('golden_values.json', golden);
console.log('done.');
