// Gooby sticker-book catalog (PLAN3 §C5.1, binding — agent V3/G34). The 28
// original ids are FROZEN in table order; V5/STICKERS wave 1 appends 20 more
// regular stickers AFTER them; V6/F1 (PLAN6 Wave F) appends 36 more on six
// themed pages AFTER those (always before the secret slot, which stays last).
// Art PNGs are committed 1:1 at public/assets/stickers/<id>.png (512×512,
// ≤ 150 KB legacy / ≤ 96 KiB for the V6 batch — §C5.2/§D6 + PLAN6 §5,
// verified by test/stickers.test.js). Pure data: no three.js/DOM imports
// (§B rule). Condition evaluation lives in systems/stickerBook.js; this file
// only describes WHAT to check.
//
// Condition spec shapes (§B5 — reuse the achievements shapes + one new):
//   { counter: '<id>', target: N }   achievements.counters[id] ≥ N
//   { special: '<id>', target: N }   engine-evaluated conditions:
//     'level'            level ≥ N
//     'fullOutfit'       N of the 3 ORIGINAL equip slots filled at once
//                        (hat/glasses/neck — §C13.3: back not required)
//     'weightMax'        weight.value ≥ N reached (latched on unlock)
//     'setsClaimed'      v2 collection sets claimed ≥ N
//     'skinsOwned'       skins.owned.length ≥ N (first purchase = 2: cream+1)
//     'gameBest'         minigames.best[def.game] ≥ N (extra field `game`)
//     'collectionEntry'  collections.entries['<set>.<entry>'] ≥ N
//                        (extra fields `set`/`entry`)
//   { event: '<hookId>' }            one-shot §C5.4 runtime hooks, delivered
//                        via store.emit('stickerHook', {id: '<hookId>'})
//                        (§E0.1-7 — G35 fires grumpyWake/rainCanopy/
//                        nightStars/towed at their sources)
//   V6/F1 specials (PLAN6 Wave F — ALL pure reads of existing slices; no new
//   fire sites anywhere outside systems/stickerBook.js):
//     'postcards'        D2 postcard-archive entries ≥ N (systems/postcards.js
//                        archiveOf); optional field `dest` restricts the count
//                        to one destination id (data/vacations.js catalog)
//     'vacationTrips'    vacation.trips (completed vacations) ≥ N
//     'park'             E1 themePark slice read ≥ N (systems/themePark.js
//                        sliceOf); field `key` picks the signal:
//                        'visits' | 'coasterRides' (rides.coaster) |
//                        'nightVisit' (latched flag, 0/1) | 'candyBought'
//     'streak'           daily.streak ≥ N (the achievements 'streak' read)
//     'playtimeMin'      profile.playtimeMin ≥ N
//     'coinsSpent'       profile.coinsSpent ≥ N
//     'outfitsOwned'     outfits.owned.length ≥ N
//     'decorPlaced'      non-default decor placed ≥ N (achievementsEngine
//                        countNonDefaultDecor — the 'decorator' read)

/**
 * @typedef {Object} StickerDef
 * @property {string} id        sticker id (§C5.1 table, verbatim)
 * @property {string} nameKey   strings key — EN/DE title per §C5.1
 * @property {string} flavorKey strings key — EN/DE flavor line per §C5.1
 * @property {string} hintKey   strings key — non-spoiler unlock hint (§C5.3)
 * @property {string} art       committed PNG path (§B5: 'assets/stickers/<id>.png')
 * @property {string} [page]    V6/F1: themed page id (STICKER_PAGES) — set on
 *   the 36 V6 rows only; MUST match the row's positional page (pinned by
 *   test/stickers.test.js). The frozen pre-V6 rows stay untouched.
 * @property {{counter?: string, special?: string, event?: string,
 *   target?: number, game?: string, set?: string, entry?: string,
 *   dest?: string, key?: string}} cond
 */

/** @type {StickerDef[]} 84 regular (28 §C5.1 + 20 V5 + 36 V6) + secret last. */
export const STICKERS = Object.freeze(
  [
    { id: 'firstNom', cond: { counter: 'feeds', target: 1 } },
    { id: 'squeakyClean', cond: { counter: 'washes', target: 1 } },
    { id: 'ballBuddy', cond: { counter: 'balls', target: 10 } },
    { id: 'sleepyhead', cond: { counter: 'sleeps', target: 1 } },
    { id: 'tenNights', cond: { counter: 'sleeps', target: 10 } },
    // §C5.4 hook: sleepFlow early-wake (grumpy) path
    { id: 'grumpMorning', cond: { event: 'grumpyWake' } },
    // health.state → 'sick' first time: the achievementsEngine wiring latches
    // counters.sickEver on every healthy/queasy → sick transition (§C5.1
    // "existing counters" ruling — no new hook needed)
    { id: 'feverFace', cond: { counter: 'sickEver', target: 1 } },
    { id: 'drGooby', cond: { counter: 'vetTrips', target: 1 } },
    { id: 'firstSprout', cond: { counter: 'harvests', target: 1 } },
    // §C5.4 hooks: roomManager garden-enter while weather=rain / band=night
    { id: 'rainyDay', cond: { event: 'rainCanopy' } },
    { id: 'starGazer', cond: { event: 'nightStars' } },
    { id: 'sayCheese', cond: { counter: 'photosTaken', target: 1 } },
    { id: 'bigTen', cond: { special: 'level', target: 10 } },
    { id: 'quarterClub', cond: { special: 'level', target: 25 } },
    { id: 'maxLevel', cond: { special: 'level', target: 40 } },
    { id: 'roadTripper', cond: { counter: 'trips', target: 1 } },
    // §C5.4 hook: shopTrip tow cutscene (3 crashes) first time
    { id: 'towTrouble', cond: { event: 'towed' } },
    // fishingPond golden catch: the fish pipeline already awards the v2
    // collection entry 'fish.goldenFish' on catch (framework meta.caught)
    { id: 'goldenCatch', cond: { special: 'collectionEntry', set: 'fish', entry: 'goldenFish', target: 1 } },
    { id: 'discoGooby', cond: { special: 'gameBest', game: 'danceParty', target: 100 } },
    // framework forwards miniGolf meta.holeInOnes into the counter (V2/G23)
    { id: 'holeInOneHero', cond: { counter: 'holeInOnes', target: 1 } },
    { id: 'parcelPro', cond: { counter: 'deliveries', target: 10 } },
    // first skin purchased: owned starts ['cream'] → length 2 after one buy
    { id: 'freshDrip', cond: { special: 'skinsOwned', target: 2 } },
    { id: 'fullFit', cond: { special: 'fullOutfit', target: 3 } },
    { id: 'maxFloof', cond: { special: 'weightMax', target: 86 } },
    { id: 'nutellaGlob', cond: { counter: 'nougatGlobs', target: 1 } },
    // purblePlace meta.perfectCakes → counters.perfectCakes (§B1 counter)
    { id: 'cakeBoss', cond: { counter: 'perfectCakes', target: 1 } },
    // shoppingSurf run completed (BOTH modes bump surfRuns — §C8.6)
    { id: 'surfStar', cond: { counter: 'surfRuns', target: 1 } },
    { id: 'albumMaster', cond: { special: 'setsClaimed', target: 4 } },
    // ── V5/STICKERS wave 1: +20 regular stickers (ids appended AFTER the 28
    // frozen §C5.1 rows, BEFORE the secret slot). RULE: only EXISTING
    // counter/gameBest condition plumbing — no new specials, no new hooks.
    // Counters are all §B1/§B2 save-schema keys already bumped by their
    // owning systems (see systems/stickerBook.js wiring map + save.js
    // V2/V3/V4_COUNTER_DEFAULTS); gameBest reads minigames.best[game].
    { id: 'snackStack', cond: { counter: 'feeds', target: 50 } },
    { id: 'cleanMachine', cond: { counter: 'washes', target: 25 } },
    { id: 'bellyLaugh', cond: { counter: 'tickles', target: 50 } },
    { id: 'dreamTeam', cond: { counter: 'sleeps', target: 25 } },
    { id: 'gardenBasket', cond: { counter: 'harvests', target: 25 } },
    { id: 'greenThumb', cond: { counter: 'waterings', target: 50 } },
    { id: 'seedStarter', cond: { counter: 'plantings', target: 10 } },
    { id: 'photoWall', cond: { counter: 'photosTaken', target: 10 } },
    { id: 'roadRegular', cond: { counter: 'trips', target: 10 } },
    { id: 'ballStorm', cond: { counter: 'balls', target: 50 } },
    // cleanTrips: achievementsEngine's shop-trip interception (0-crash trips)
    { id: 'safeDriver', cond: { counter: 'cleanTrips', target: 5 } },
    { id: 'deliveryAce', cond: { counter: 'deliveries', target: 50 } },
    // modifierPlays: §B1 v4 counter bumped by economy's modifier payout path
    { id: 'modifierMischief', cond: { counter: 'modifierPlays', target: 5 } },
    // gameBest thresholds sit at "strong run" level per each game's score
    // scale (carrotCatch typical ≈ 45; memoryMatch max 48; goobySays ≈ 88)
    { id: 'carrotChampion', cond: { special: 'gameBest', game: 'carrotCatch', target: 60 } },
    { id: 'memoryMaster', cond: { special: 'gameBest', game: 'memoryMatch', target: 40 } },
    { id: 'saysSuperstar', cond: { special: 'gameBest', game: 'goobySays', target: 100 } },
    { id: 'questScout', cond: { counter: 'questsDone', target: 10 } },
    { id: 'getWellSoon', cond: { counter: 'cures', target: 3 } },
    // radioMinutes: §C-SYS1.7 accrual (1/min while the radio plays)
    { id: 'radioBunny', cond: { counter: 'radioMinutes', target: 30 } },
    { id: 'codeWhisperer', cond: { counter: 'codesRedeemed', target: 1 } },
    // ── end V5/STICKERS wave 1 ──
    // ── V6/F1 (PLAN6 Wave F): +36 regular stickers on six themed pages,
    // appended AFTER the 48 frozen pre-V6 rows and BEFORE the secret slot
    // (append-only positional slicing — no re-homing of the existing pages).
    // RULE: every condition is a PURE READ of existing state — D2's postcard
    // archive, E1's themePark slice, minigame bests, §B1/§B2 counters and
    // trivial profile/daily/outfits/furniture reads. No new fire sites.
    // ── Page 9 „Reise" (Travel) — D2 postcard archive + vacation slice ──
    { id: 'beachPostcard', page: 'travel', cond: { special: 'postcards', dest: 'beach', target: 1 } },
    { id: 'harborPostcard', page: 'travel', cond: { special: 'postcards', dest: 'harbor', target: 1 } },
    { id: 'bakeryPostcard', page: 'travel', cond: { special: 'postcards', dest: 'bakery', target: 1 } },
    { id: 'nightSkyPostcard', page: 'travel', cond: { special: 'postcards', dest: 'nightSky', target: 1 } },
    { id: 'frequentFlyer', page: 'travel', cond: { special: 'vacationTrips', target: 3 } },
    { id: 'penPal', page: 'travel', cond: { special: 'postcards', target: 10 } },
    // ── Page 10 „Funkelpark" — E1 themePark slice reads only. NOTE: the
    // handsUp sticker keys off rides.coaster ≥ 3 (E2's ride reports no
    // hands-up count — see the E1 hand-off; the hint copy says so honestly).
    { id: 'parkFirstVisit', page: 'funkelpark', cond: { special: 'park', key: 'visits', target: 1 } },
    { id: 'loopStar', page: 'funkelpark', cond: { special: 'park', key: 'coasterRides', target: 1 } },
    { id: 'handsUp', page: 'funkelpark', cond: { special: 'park', key: 'coasterRides', target: 3 } },
    { id: 'candyDay', page: 'funkelpark', cond: { special: 'park', key: 'candyBought', target: 3 } },
    { id: 'nightLights', page: 'funkelpark', cond: { special: 'park', key: 'nightVisit', target: 1 } },
    { id: 'parkExplorer', page: 'funkelpark', cond: { special: 'park', key: 'visits', target: 5 } },
    // ── Page 11 „Arcade-Sterne" (Arcade Stars) — minigame bests + §B1
    // counters (gameBest targets sit at "strong run" level vs each game's
    // data/difficultyTargets.js normal target: lanternFloat 75, snailMail 80,
    // pipeFlow 100) ──
    { id: 'lanternKeeper', page: 'arcadeStars', cond: { special: 'gameBest', game: 'lanternFloat', target: 60 } },
    { id: 'snailCourier', page: 'arcadeStars', cond: { special: 'gameBest', game: 'snailMail', target: 60 } },
    { id: 'ghostWhisperer', page: 'arcadeStars', cond: { counter: 'ghostsCaught', target: 25 } },
    { id: 'harborMaster', page: 'arcadeStars', cond: { counter: 'cratesShipped', target: 50 } },
    { id: 'rocketHero', page: 'arcadeStars', cond: { counter: 'rescues', target: 15 } },
    { id: 'pipeDreamer', page: 'arcadeStars', cond: { special: 'gameBest', game: 'pipeFlow', target: 70 } },
    // ── Page 12 „Kuschelleben" (Cozy Life) — §B1/§B2 counters + daily
    // streak + the achievements 'decorator' read ──
    { id: 'weekStreak', page: 'cozyLife', cond: { special: 'streak', target: 7 } },
    { id: 'medsMaster', page: 'cozyLife', cond: { counter: 'medsGiven', target: 10 } },
    { id: 'marketDay', page: 'cozyLife', cond: { counter: 'sells', target: 25 } },
    { id: 'memoryKeeper', page: 'cozyLife', cond: { counter: 'galleryPhotos', target: 40 } },
    { id: 'interiorDesigner', page: 'cozyLife', cond: { special: 'decorPlaced', target: 20 } },
    { id: 'storyTeller', page: 'cozyLife', cond: { counter: 'recapsSeen', target: 3 } },
    // ── Page 13 „Schlemmerei" (Foodie Feast) — EXISTING signals only
    // (gameBest + cakesServed/nougatGlobs), zero new evaluators (PLAN6) ──
    { id: 'teaTime', page: 'foodieFeast', cond: { special: 'gameBest', game: 'teaParty', target: 60 } },
    { id: 'pancakeMountain', page: 'foodieFeast', cond: { special: 'gameBest', game: 'pancakeTower', target: 40 } },
    { id: 'burgerBoss', page: 'foodieFeast', cond: { special: 'gameBest', game: 'burgerBuild', target: 60 } },
    { id: 'veggieChef', page: 'foodieFeast', cond: { special: 'gameBest', game: 'veggieChop', target: 70 } },
    { id: 'cakeParade', page: 'foodieFeast', cond: { counter: 'cakesServed', target: 25 } },
    { id: 'nougatFlood', page: 'foodieFeast', cond: { counter: 'nougatGlobs', target: 10 } },
    // ── Page 14 „Beste Freunde" (Best Friends) — the three trivial PLAN6
    // profile/outfits specials + tickles counter + daily streak ──
    { id: 'bestBuddies', page: 'bestFriends', cond: { special: 'playtimeMin', target: 300 } },
    { id: 'inseparable', page: 'bestFriends', cond: { special: 'playtimeMin', target: 1500 } },
    { id: 'tickleTornado', page: 'bestFriends', cond: { counter: 'tickles', target: 200 } },
    { id: 'monthStreak', page: 'bestFriends', cond: { special: 'streak', target: 30 } },
    { id: 'hatParade', page: 'bestFriends', cond: { special: 'outfitsOwned', target: 10 } },
    { id: 'bigSpender', page: 'bestFriends', cond: { special: 'coinsSpent', target: 3000 } },
    // ── end V6/F1 ──
    // V4/G53 (PLAN4 §C-SYS5.4, binding): sticker herzGooby is a BONUS
    // sticker OUTSIDE the regular count — secret: true keeps it out of
    // TOTAL_BOOK_STICKERS (header shows n/48 since V5; stickerBookFull stays
    // target 28); it unlocks ONLY via the 'herzGooby' code word (cond.code
    // reads codes.redeemed — §B6/§C-SYS5.2). Stays LAST in table order.
    { id: 'herzGooby', secret: true, cond: { code: 'herzGooby' } },
  ].map((s) =>
    Object.freeze({
      ...s,
      cond: Object.freeze(s.cond),
      nameKey: `stickerbook.${s.id}.name`,
      flavorKey: `stickerbook.${s.id}.flavor`,
      hintKey: `stickerbook.${s.id}.hint`,
      art: `assets/stickers/${s.id}.png`,
    })
  )
);

/** @type {Record<string, StickerDef>} id → def lookup. */
export const STICKERS_BY_ID = Object.freeze(
  Object.fromEntries(STICKERS.map((s) => [s.id, s]))
);

/**
 * @param {string} id
 * @returns {StickerDef|undefined}
 */
export function getSticker(id) {
  return STICKERS_BY_ID[id];
}

/**
 * Total book stickers (V6: 84 — header shows n/84). V4/G53 (§C-SYS5.4): the
 * secret herzGooby bonus sticker is OUTSIDE the count — the header gains a
 * „+💗" suffix once unlocked, stickerBookFull keeps target 28.
 */
export const TOTAL_BOOK_STICKERS = STICKERS.filter((s) => !s.secret).length;

/**
 * §C5.3 page layout in a 2×3 grid — the 84 REGULAR stickers only.
 * V5/STICKERS: 8 full pages of 6 (was 6/6/6/6/4); V6/F1: 14 full pages of 6
 * (append-only — the frozen 48 keep their positions/pages). V4/G53
 * (§C-SYS5.4): the secret slot is NOT paged here; ui/albumScreen.js appends
 * it explicitly to the LAST page as a mystery „?" slot with „Geheim" styling
 * while locked.
 */
export const STICKER_PAGE_SIZES = Object.freeze([6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6]);

/**
 * @typedef {Object} StickerPageDef
 * @property {string} id        page id ('classic1'…'classic8' legacy, then
 *   the six PLAN6 themed ids)
 * @property {string|null} titleKey strings key for the page title — null on
 *   the legacy pages (UI falls back to t('stickerbook.page', {n}))
 * @property {string} icon      ui/icons.js glyph name (page chip + the
 *   locked-slot watermark — shared UI glyphs, NEVER the sticker art)
 * @property {string} tint      pastel accent (#rrggbb) for the page chip and
 *   the locked-slot mystery tint (page-generic — leaks nothing per sticker)
 */

/**
 * V6/F1 page catalog — POSITIONAL: entry i describes stickerPages()[i]
 * (append-only slicing stays the §C5.3 source of truth; this table only adds
 * presentation data for the album's page rail + tinted mystery boxes).
 * @type {StickerPageDef[]}
 */
export const STICKER_PAGES = Object.freeze(
  [
    { id: 'classic1', titleKey: null, icon: 'hunger', tint: '#F2CDB4' },
    { id: 'classic2', titleKey: null, icon: 'stethoscope', tint: '#C9E3D2' },
    { id: 'classic3', titleKey: null, icon: 'trophy', tint: '#EFDFAE' },
    { id: 'classic4', titleKey: null, icon: 'shirt', tint: '#D9CFF0' },
    { id: 'classic5', titleKey: null, icon: 'nutellaJar', tint: '#E4C9B4' },
    { id: 'classic6', titleKey: null, icon: 'sprout', tint: '#CDE6BE' },
    { id: 'classic7', titleKey: null, icon: 'car', tint: '#C2D6EE' },
    { id: 'classic8', titleKey: null, icon: 'star', tint: '#E3C6DE' },
    { id: 'travel', titleKey: 'stickerbook.pageTitle.travel', icon: 'suitcase', tint: '#AFD8E8' },
    { id: 'funkelpark', titleKey: 'stickerbook.pageTitle.funkelpark', icon: 'sparkle', tint: '#E8C9F0' },
    { id: 'arcadeStars', titleKey: 'stickerbook.pageTitle.arcadeStars', icon: 'gamepad', tint: '#C9CFF0' },
    { id: 'cozyLife', titleKey: 'stickerbook.pageTitle.cozyLife', icon: 'cottage', tint: '#F0D9C9' },
    { id: 'foodieFeast', titleKey: 'stickerbook.pageTitle.foodieFeast', icon: 'candy', tint: '#F0E3B8' },
    { id: 'bestFriends', titleKey: 'stickerbook.pageTitle.bestFriends', icon: 'heart', tint: '#F4BFCD' },
  ].map((p) => Object.freeze(p))
);

/**
 * The catalog split into the §C5.3 pages (table order, non-secret only).
 * @returns {StickerDef[][]} 14 arrays of 6 defs
 */
export function stickerPages() {
  const regular = STICKERS.filter((s) => !s.secret); // secret slot excluded
  const pages = [];
  let at = 0;
  for (const size of STICKER_PAGE_SIZES) {
    pages.push(regular.slice(at, at + size));
    at += size;
  }
  return pages;
}
