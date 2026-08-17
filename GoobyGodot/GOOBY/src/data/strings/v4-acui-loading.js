// V4/AC-3: v4-acui-loading.js — OWNED BY AGENT AC-3.
// Loading-veil strings (the cozy IN/OUT transition curtain in ui/loadingVeil.js):
// home-return + trip card lines and their rotating flavor tips. Consumed via
// loadingVeil.js's local tx() fallback until a later strings sweep spreads
// them into strings.js — strings.js itself is frozen (PLAN4 §E0.1-8).
// Game-mode veil lines REUSE POLISH-D's v4-ui2.js keys (imported by the
// veil, never duplicated here). Always EN + DE.
// No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // shared "Loading…" label under the progress bar (mirrors 'mg.loading',
  // which lives in the frozen-elsewhere v4-difficulty module)
  'acui.loading.label': 'Loading…',
  // OUT veil — returning to the house (results "Home", pause quit)
  'acui.loading.homeTitle': 'Home sweet home',
  'acui.loading.homeReady': 'Heading home…',
  'acui.loading.tipHome1': 'Fluffing the pillows…',
  'acui.loading.tipHome2': 'Putting the kettle on…',
  'acui.loading.tipHome3': 'Watering the flowers…',
  // trip veil — shop/vet travel transitions (systems/shopTrip.js)
  'acui.loading.tripTitle': 'Off we go!',
  'acui.loading.tripReady': 'Time for a little outing…',
  'acui.loading.tipTrip1': 'Packing snacks for the ride…',
  'acui.loading.tipTrip2': 'Checking the shopping list…',
  'acui.loading.tipTrip3': 'Lacing up the tiny shoes…',
};

/** @type {Record<string, string>} */
export const DE = {
  'acui.loading.label': 'Lädt…',
  'acui.loading.homeTitle': 'Trautes Heim',
  'acui.loading.homeReady': 'Auf dem Heimweg…',
  'acui.loading.tipHome1': 'Kissen werden aufgeschüttelt…',
  'acui.loading.tipHome2': 'Der Tee wird aufgesetzt…',
  'acui.loading.tipHome3': 'Die Blumen werden gegossen…',
  'acui.loading.tripTitle': 'Auf geht’s!',
  'acui.loading.tripReady': 'Zeit für einen kleinen Ausflug…',
  'acui.loading.tipTrip1': 'Snacks für unterwegs werden eingepackt…',
  'acui.loading.tipTrip2': 'Der Einkaufszettel wird geprüft…',
  'acui.loading.tipTrip3': 'Die kleinen Schuhe werden geschnürt…',
};
