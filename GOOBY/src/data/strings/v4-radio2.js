// V4/POLISH-A (radio transport) — prev button + seek bar copy for the radio
// screen. Add keys ONLY here (ownership: POLISH-A), always EN + DE.
// `src/data/strings.js` is frozen after G53's one-time 4.0 edit, so this
// module is NOT spread into the global table: radioScreen.js consumes it
// through its local tx() fallback (the same same-wave pattern v4-radio.js
// used before G53 spread it globally).

/** @type {Record<string, string>} */
export const EN = {
  'radio.prev': 'Previous track',
  'radio.seek': 'Track position',
};

/** @type {Record<string, string>} */
export const DE = {
  'radio.prev': 'Vorheriger Track',
  'radio.seek': 'Track-Position',
};
