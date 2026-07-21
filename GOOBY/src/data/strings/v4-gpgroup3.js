// GOOBY V4/GAME-POLISH-3: v4-gpgroup3.js — OWNED BY AGENT GAME-POLISH-3.
// Juice-beat strings for the six GP3 games (runner, bunnyHop, starHopper,
// harborHopper, trampoline, basketBounce). Consumed via each game's local
// tx() fallback (v4-ui2/v4-arcade2 precedent) until a later strings sweep
// spreads them into strings.js — strings.js itself is frozen (PLAN4 §E0.1-8).
// Always EN + DE. No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // GP3 runner: distance-milestone chime floater (every 100 m)
  'gp3.runner.milestone': '{m} m!',
  // GP3 bunnyHop: the §C6.1 every-10-gates gap narrowing, finally announced
  'gp3.hop.gapNarrow': 'The gap narrows!',
  // GP3 basketBounce: swish-streak on-fire banner (visual only)
  'gp3.basket.onFire': 'On fire!',
};

/** @type {Record<string, string>} */
export const DE = {
  'gp3.runner.milestone': '{m} m!',
  'gp3.hop.gapNarrow': 'Die Lücke wird enger!',
  'gp3.basket.onFire': 'Heißgelaufen!',
};
