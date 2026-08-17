// V4/GAME-POLISH-2: v4-gpgroup2.js — OWNED BY AGENT GAME-POLISH-2.
// Juice/polish strings for the group-2 games (burgerBuild, pancakeTower,
// veggieChop, purblePlace, memoryMatch, goobySays). Consumed via each game's
// local tx() fallback (G52 pattern) until a later strings sweep spreads them
// into strings.js — strings.js itself is frozen (PLAN4 §E0.1-8).
// Always EN + DE. No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // veggieChop: 3+ veggies sliced in ONE swipe (beyond the x2 combo banner)
  'gp2.chop.triple': 'Triple chop!',
};

/** @type {Record<string, string>} */
export const DE = {
  'gp2.chop.triple': 'Dreifach-Schnitt!',
};
