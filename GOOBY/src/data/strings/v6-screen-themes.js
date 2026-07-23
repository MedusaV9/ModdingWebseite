// V6/B3 — screen-theme detail strings (PLAN6 Wave B / B3) — OWNED BY THE
// SCREEN-WORLDS AGENT. New visible labels for the three flagship bespoke
// screens: the shop's aisle signs (one per category tab — the sign echoes
// the active category) and the profile's passport chrome (cover wordmark,
// field labels, entry-stamp captions). The MRZ footer is DATA formatting
// (mrzLines in ui/profileScreen.js), not strings. Always EN + DE; spread
// into data/strings.js AFTER the v6-cutscenes module (import committed by
// B2 per the PLAN6 appendix rule). No other agent may edit this module.
//
// test/screenThemeDetails.test.js asserts every shop category tab id has a
// thm.shop.aisle.<id> sign in BOTH dictionaries — add the sign here first
// when a new shop tab ever lands.

/** @type {Record<string, string>} */
export const EN = {
  // shop — aisle header signs (thm.shop.aisle.<tabId>, cozy-IKEA voice)
  'thm.shop.aisle.food': 'Food Aisle',
  'thm.shop.aisle.care': 'Care Corner',
  'thm.shop.aisle.furniture': 'Furniture Hall',
  'thm.shop.aisle.decor': 'Wall + Floor Studio',
  'thm.shop.aisle.outfits': 'Outfit Boutique',
  'thm.shop.aisle.skins': 'Fur Salon',

  // profile — passport chrome
  'thm.passport.cover': 'GOOBY PASS',
  'thm.passport.kind': 'Passport',
  'thm.passport.field.name': 'Name',
  'thm.passport.field.since': 'Member since',
  'thm.passport.field.fur': 'Fur',
  'thm.passport.stamps': 'Entry stamps',
  'thm.passport.stamp.vacations': 'Vacation ×{n}',
  'thm.passport.stamp.recap': 'Recap L{level}',
  'thm.passport.stamp.awards': '{n} awards',
};

/** @type {Record<string, string>} */
export const DE = {
  // shop — aisle header signs (thm.shop.aisle.<tabId>)
  'thm.shop.aisle.food': 'Essens-Gang',
  'thm.shop.aisle.care': 'Pflege-Ecke',
  'thm.shop.aisle.furniture': 'Möbel-Halle',
  'thm.shop.aisle.decor': 'Wand + Boden Studio',
  'thm.shop.aisle.outfits': 'Outfit-Boutique',
  'thm.shop.aisle.skins': 'Fell-Salon',

  // profile — passport chrome
  'thm.passport.cover': 'GOOBY PASS',
  'thm.passport.kind': 'Reisepass',
  'thm.passport.field.name': 'Name',
  'thm.passport.field.since': 'Dabei seit',
  'thm.passport.field.fur': 'Fell',
  'thm.passport.stamps': 'Einreise-Stempel',
  'thm.passport.stamp.vacations': 'Urlaub ×{n}',
  'thm.passport.stamp.recap': 'Rückblick L{level}',
  'thm.passport.stamp.awards': '{n} Erfolge',
};
