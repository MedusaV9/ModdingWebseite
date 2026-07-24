// V4/POLISH-J: v4-recap2.js — OWNED BY AGENT POLISH-J.
// Recap-cinematic polish strings (upgraded §C-SYS2.7 end card: highlights
// heading, played-song credit line, and the short per-stat chip labels).
// Consumed via recapOverlay.js' local tx() fallback (the G52 pattern —
// strings.js itself is frozen, PLAN4 §E0.1-8) until a later strings sweep
// spreads them into strings.js. Always EN + DE. The chip labels are SHORT
// display nouns for the STAT_CATALOG ids (§C-SYS2.4) — the full sentence
// templates stay in v4-recap.js untouched.
// No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // ── POLISH-J end card ─────────────────────────────────────────────────────
  'recap2.endcard.highlights': 'Highlights',
  'recap2.endcard.song': '{name}',
  // ── POLISH-J short chip labels (one per §C-SYS2.4 STAT_CATALOG id) ───────
  'recap2.stat.days': 'Days',
  'recap2.stat.games': 'Games',
  'recap2.stat.coinsEarned': 'Coins',
  'recap2.stat.tickles': 'Cuddles',
  'recap2.stat.feeds': 'Meals',
  'recap2.stat.harvests': 'Harvests',
  'recap2.stat.stickers': 'Stickers',
  'recap2.stat.quests': 'Quests',
  'recap2.stat.washes': 'Baths',
  'recap2.stat.sleeps': 'Nights',
  'recap2.stat.trips': 'Trips',
  'recap2.stat.distance': 'Meters',
  'recap2.stat.photos': 'Photos',
  'recap2.stat.deliveries': 'Parcels',
  'recap2.stat.cures': 'Recoveries',
  'recap2.stat.cakes': 'Cakes',
  'recap2.stat.nougat': 'Nougat',
  'recap2.stat.coinsSpent': 'Spent',
};

/** @type {Record<string, string>} */
export const DE = {
  // ── POLISH-J end card ─────────────────────────────────────────────────────
  'recap2.endcard.highlights': 'Highlights',
  'recap2.endcard.song': '{name}',
  // ── POLISH-J short chip labels (one per §C-SYS2.4 STAT_CATALOG id) ───────
  'recap2.stat.days': 'Tage',
  'recap2.stat.games': 'Spiele',
  'recap2.stat.coinsEarned': 'Münzen',
  'recap2.stat.tickles': 'Kuscheln',
  'recap2.stat.feeds': 'Mahlzeiten',
  'recap2.stat.harvests': 'Ernten',
  'recap2.stat.stickers': 'Sticker',
  'recap2.stat.quests': 'Quests',
  'recap2.stat.washes': 'Bäder',
  'recap2.stat.sleeps': 'Nächte',
  'recap2.stat.trips': 'Ausflüge',
  'recap2.stat.distance': 'Meter',
  'recap2.stat.photos': 'Fotos',
  'recap2.stat.deliveries': 'Pakete',
  'recap2.stat.cures': 'Genesungen',
  'recap2.stat.cakes': 'Torten',
  'recap2.stat.nougat': 'Nougat',
  'recap2.stat.coinsSpent': 'Ausgegeben',
};
