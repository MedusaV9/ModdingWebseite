// V4/POLISH-H (recap-heard radio gate) — lock-badge copy for recap songs the
// player has not heard in a recap yet. Add keys ONLY here (ownership:
// POLISH-H), always EN + DE. `src/data/strings.js` is frozen after G53's
// one-time 4.0 edit, so this module is NOT spread into the global table:
// radioScreen.js consumes it through its local tx() fallback (the same
// same-wave pattern as v4-radio2.js).

/** @type {Record<string, string>} */
export const EN = {
  'radio.recapLocked': 'Unlock from a recap',
};

/** @type {Record<string, string>} */
export const DE = {
  'radio.recapLocked': 'Aus einem Rückblick freischalten',
};
