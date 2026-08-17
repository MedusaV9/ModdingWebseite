// V4/POLISH-E: v4-arcade2.js — OWNED BY AGENT POLISH-E.
// Minigame-framework arcade strings, part 2: the shared 3-strikes →
// teleport-to-loading flow (strike counter banner + teleport line) and the
// landscape-mode „Bitte dreh dein Handy" rotate overlay. Consumed via the
// framework's local tx() fallback until a later strings sweep spreads them
// into strings.js — strings.js itself is frozen (PLAN4 §E0.1-8).
// Always EN + DE. No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // POLISH-E shared strike counter (banner on strikes 1..max−1)
  'arcade2.strike': 'Strike {n}/{max}!',
  // POLISH-E 3rd strike — the teleport-to-loading cutscene line
  'arcade2.strikes.teleport': '3 strikes — teleporting you out!',
  // POLISH-E rotate-your-phone gate (landscape games on a portrait viewport)
  'arcade2.rotate.title': 'Please rotate your phone',
  'arcade2.rotate.hint': 'This game plays in landscape',
  'arcade2.rotate.continue': 'Tap to continue anyway',
};

/** @type {Record<string, string>} */
export const DE = {
  'arcade2.strike': 'Patzer {n}/{max}!',
  'arcade2.strikes.teleport': '3 Patzer — du wirst rausteleportiert!',
  'arcade2.rotate.title': 'Bitte dreh dein Handy',
  'arcade2.rotate.hint': 'Dieses Spiel läuft im Querformat',
  'arcade2.rotate.continue': 'Tippen, um trotzdem zu starten',
};
