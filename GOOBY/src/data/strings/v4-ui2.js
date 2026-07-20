// V4/POLISH-D: v4-ui2.js — OWNED BY AGENT POLISH-D.
// UI-transition + themed game-loading-screen strings (loading headline +
// rotating tips under the progress bar). Consumed via the framework's local
// tx() fallback until a later strings sweep spreads them into strings.js —
// strings.js itself is frozen (PLAN4 §E0.1-8). Always EN + DE.
// No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // POLISH-D loading-card headline (game title renders above it)
  'ui2.loading.getReady': 'Get ready!',
  // POLISH-D rotating loading tips (picked per launch)
  'ui2.loading.tip1': 'Tip: You can pause any time with the ⏸ button.',
  'ui2.loading.tip2': 'Tip: The first round of each game every day pays double coins!',
  'ui2.loading.tip3': 'Tip: Hard mode pays ×1.3 coins — Endless is pure bragging rights.',
};

/** @type {Record<string, string>} */
export const DE = {
  'ui2.loading.getReady': 'Mach dich bereit!',
  'ui2.loading.tip1': 'Tipp: Mit ⏸ kannst du jederzeit pausieren.',
  'ui2.loading.tip2': 'Tipp: Die erste Runde pro Spiel am Tag bringt doppelte Münzen!',
  'ui2.loading.tip3': 'Tipp: Schwer zahlt ×1,3 Münzen — Endlos ist für den Ruhm.',
};
