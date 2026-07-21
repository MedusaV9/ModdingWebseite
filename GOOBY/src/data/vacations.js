// V5/VACATION — vacation destination catalog (PLAN5 idea IDEA-01): the four
// bookable airport trips. Pure data, same shape rules as data/crops.js /
// data/skins.js — frozen rows, no DOM/three imports, node:test hits it
// directly (test/vacation.test.js). Prices per the coordinator ruling
// (Sol: 350–600 too high) — 180/220/280/350; trips last 3 or 4 REAL days.
//
// Every id doubles as the strings suffix: 'vacation.dest.<id>.name' /
// '.sub' / 'vacation.postcard.<id>' live in strings/v5-vacation.js (EN+DE).
// `icon` must be a ui/icons.js glyph name (icons.test.js-safe set only).
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
 */

/** @type {readonly VacationDest[]} */
export const VACATIONS = Object.freeze([
  Object.freeze({
    id: 'beach', icon: 'fish', price: 180, days: 3,
    souvenirCoins: 30, color: '#3FC9C0',
  }),
  Object.freeze({
    id: 'meadowTrip', icon: 'sprout', price: 220, days: 3,
    souvenirCoins: 40, color: '#8FCB6B',
  }),
  Object.freeze({
    id: 'bigCity', icon: 'car', price: 280, days: 4,
    souvenirCoins: 55, color: '#FF9BD0',
  }),
  Object.freeze({
    id: 'space', icon: 'moon', price: 350, days: 4,
    souvenirCoins: 70, color: '#B9A7F0',
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
