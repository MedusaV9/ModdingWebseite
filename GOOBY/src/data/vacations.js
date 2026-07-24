// V5/VACATION — vacation destination catalog (PLAN5 idea IDEA-01): the
// bookable airport trips. Pure data, same shape rules as data/crops.js /
// data/skins.js — frozen rows, no DOM/three imports, node:test hits it
// directly (test/vacation.test.js). Prices per the coordinator ruling
// (Sol: 350–600 too high) — the 180–350 band; trips last 3 or 4 REAL days.
//
// V6/B2 (PLAN6 Wave B): the canonical NINE-destination travel board — every
// recap place becomes bookable. The catalog grows 4 → 9: the original four
// rows stay byte-identical in behavior (ungated, same prices/days), and five
// new rows land for the previously unbooked recap biomes. Two new fields:
//   `biome`            the recap vignette biome id this destination shows
//                      (systems/recapDirector.js DEFAULT_BIOMES — the 8 ids
//                      meadow/city/harbor/space/spookGarden/bakery/nightSky/
//                      toyRoom map 1:1 onto 8 destinations; `beach` is the
//                      bonus NON-recap ninth place, so its biome is null.
//                      Per the EVAL ruling harbor is its OWN destination —
//                      never collapsed into beach).
//   `unlockRecapLevel` recap.lastRecapLevel gate (0 = always bookable). The
//                      five new rows unlock at 15/25/30/35/40 following the
//                      milestone→vignette order (milestone N discovers
//                      DEFAULT_BIOMES[N/5 − 1] — idea 09 §c): harbor 15,
//                      spookGarden 25, bakery 30, nightSky 35, toyRoom 40.
//                      Locked rows render as mystery cards (ui/airportScreen)
//                      and stay bookable through the engine only via ids the
//                      UI never exposes — economy paths are untouched.
//
// Every id doubles as the strings suffix: 'vacation.dest.<id>.name' /
// '.sub' / 'vacation.postcard.<id>' live in strings/v5-vacation.js for the
// original four and strings/v6-vacations.js for the V6 five (EN+DE); the
// V6.1/A2 locked-card teasers ('vacation.dest.<id>.teaser') live in
// strings/v6_1-content.js.
// `icon` must be a ui/icons.js glyph name (icons.test.js-safe set only).
// V6.1/A2 (FINAL-WAVE G1): every destination now carries its OWN authored
// glyph (sandcastle/picnicBasket/skyline/rocket/lighthouse/pumpkin/
// croissant/shootingStar/toyBlock) — the old borrowed fish/sprout/car/moon
// set retires from this catalog; board cards, booked chip and postcard
// rack all read `getVacation(id).icon`, so they upgrade for free.
// `souvenirCoins` is the coin souvenir paid at pickup through
// economy.award(store, …, 'souvenir') — always well below `price` so a
// vacation can never be a coin arbitrage loop.

/**
 * @typedef {Object} VacationDest
 * @property {string} id        catalog id + strings suffix
 * @property {string} icon      ui/icons.js glyph name (authored set)
 * @property {number} price     booking price in coins (§ ruling: 180–350)
 * @property {number} days      trip length in REAL days (3 or 4)
 * @property {number} souvenirCoins coin souvenir paid at pickup (< price)
 * @property {string} color     card accent (GOOBY palette pastels)
 * @property {string|null} biome recap vignette biome id (null = non-recap)
 * @property {number} unlockRecapLevel recap.lastRecapLevel gate (0 = open)
 */

/** @type {readonly VacationDest[]} */
export const VACATIONS = Object.freeze([
  Object.freeze({
    id: 'beach', icon: 'sandcastle', price: 180, days: 3,
    souvenirCoins: 30, color: '#3FC9C0', biome: null, unlockRecapLevel: 0,
  }),
  Object.freeze({
    id: 'meadowTrip', icon: 'picnicBasket', price: 220, days: 3,
    souvenirCoins: 40, color: '#8FCB6B', biome: 'meadow', unlockRecapLevel: 0,
  }),
  Object.freeze({
    id: 'bigCity', icon: 'skyline', price: 280, days: 4,
    souvenirCoins: 55, color: '#FF9BD0', biome: 'city', unlockRecapLevel: 0,
  }),
  Object.freeze({
    id: 'space', icon: 'rocket', price: 350, days: 4,
    souvenirCoins: 70, color: '#B9A7F0', biome: 'space', unlockRecapLevel: 0,
  }),
  // ── V6/B2: the five new recap-place destinations (gates 15/25/30/35/40) ──
  Object.freeze({
    id: 'harbor', icon: 'lighthouse', price: 200, days: 3,
    souvenirCoins: 35, color: '#6FB5E0', biome: 'harbor', unlockRecapLevel: 15,
  }),
  Object.freeze({
    id: 'spookGarden', icon: 'pumpkin', price: 240, days: 3,
    souvenirCoins: 45, color: '#9B8CD8', biome: 'spookGarden', unlockRecapLevel: 25,
  }),
  Object.freeze({
    id: 'bakery', icon: 'croissant', price: 260, days: 3,
    souvenirCoins: 50, color: '#E8A25F', biome: 'bakery', unlockRecapLevel: 30,
  }),
  Object.freeze({
    id: 'nightSky', icon: 'shootingStar', price: 300, days: 4,
    souvenirCoins: 60, color: '#7C8FE0', biome: 'nightSky', unlockRecapLevel: 35,
  }),
  Object.freeze({
    id: 'toyRoom', icon: 'toyBlock', price: 320, days: 4,
    souvenirCoins: 65, color: '#F97B7B', biome: 'toyRoom', unlockRecapLevel: 40,
  }),
]);

/** @type {readonly string[]} */
export const VACATION_IDS = Object.freeze(VACATIONS.map((v) => v.id));

const BY_ID = new Map(VACATIONS.map((v) => [v.id, v]));

/**
 * Catalog lookup.
 * @param {string} id
 * @returns {VacationDest|undefined}
 */
export function getVacation(id) {
  return BY_ID.get(id);
}

/**
 * V6/B2 — the pure lock decision for the airport board: a destination is
 * bookable once the player's highest completed recap milestone
 * (recap.lastRecapLevel) reaches the row's unlockRecapLevel. Ungated rows
 * (gate 0/absent) are always unlocked; junk inputs fail CLOSED for gated
 * rows (an unreadable recap level never reveals a mystery card early).
 * @param {VacationDest|undefined|null} dest catalog row
 * @param {number} lastRecapLevel recap.lastRecapLevel (junk → 0)
 * @returns {boolean}
 */
export function isVacationUnlocked(dest, lastRecapLevel) {
  const gate = Math.max(0, Math.floor(Number(dest?.unlockRecapLevel) || 0));
  if (gate === 0) return true;
  const level = Math.max(0, Math.floor(Number(lastRecapLevel) || 0));
  return level >= gate;
}
