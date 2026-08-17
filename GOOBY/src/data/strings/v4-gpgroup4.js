// V4/GAME-POLISH-4: v4-gpgroup4.js — OWNED BY AGENT GAME-POLISH-4.
// Juice/polish strings for the group-4 games (goalieGooby, miniGolf,
// rocketRescue, danceParty, pipeFlow). Consumed via each game's local tx()
// fallback until a later strings sweep spreads them into strings.js —
// strings.js itself is frozen (PLAN4 §E0.1-8).
// Always EN + DE. No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // rocketRescue: bonus-eligible soft touchdown label (rides with the +5)
  'gp4.rocket.soft': 'Butter landing!',
  // pipeFlow: end-of-round tap-efficiency bonus reveal
  'gp4.pipe.bonus': 'Efficiency bonus +{n}!',
};

/** @type {Record<string, string>} */
export const DE = {
  'gp4.rocket.soft': 'Butterweich gelandet!',
  'gp4.pipe.bonus': 'Effizienz-Bonus +{n}!',
};
