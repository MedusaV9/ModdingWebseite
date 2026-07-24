// V6/C4 — six-game juice-pass strings (PLAN6 Wave C / C4) — OWNED BY THE
// GAME-JUICE AGENT. Float-text and celebration labels for the measured
// bottom-six arcade games (memoryMatch, goobySays, pipeFlow, miniGolf,
// cityDrive+deliveryRush, veggieChop). Always EN + DE; spread into
// data/strings.js AFTER the v6-screen-themes module (import committed by
// C3 per the PLAN6 appendix rule). Until that lands, each juiced game
// resolves these keys through its module-local tx() fallback (G52
// pattern). No other agent may edit this module.
//
// test/gamePolish6.test.js asserts EN/DE key parity for this module.

/** @type {Record<string, string>} */
export const EN = {
  'v6.juice.pair': 'Pair!',
  'v6.juice.streak': 'Streak ×{n}!',
  'v6.juice.flow': 'Flow!',
  'v6.juice.arrived': 'Arrived!',
  'v6.juice.delivered': 'Delivered!',
  'v6.juice.frenzy': 'Frenzy!',
};

/** @type {Record<string, string>} */
export const DE = {
  'v6.juice.pair': 'Paar!',
  'v6.juice.streak': 'Serie ×{n}!',
  'v6.juice.flow': 'Läuft!',
  'v6.juice.arrived': 'Angekommen!',
  'v6.juice.delivered': 'Geliefert!',
  'v6.juice.frenzy': 'Rausch!',
};
