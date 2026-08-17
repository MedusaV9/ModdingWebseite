// V6/E3: v6-park.js (PLAN6 Wave E — Funkelpark) — OWNED BY AGENT E3.
// Candy Alley strings: stall sheet + stall signage (park.*) and the three
// park-exclusive food names (food.<id> pattern — data/foods.js nameKey
// contract), plus E2's coaster caption keys as a labeled block per the
// appendix rule. E1 commits this module's import pair into strings.js.
// Always EN + DE. No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // --- park foods (data/foods.js V6_PARK_FOODS nameKeys) ---
  'food.cottonCandy': 'Cotton Candy',
  'food.softServe': 'Soft Serve',
  'food.waffle': 'Waffle',

  // --- Candy Alley stall sheet + signage (E3) ---
  'park.alley.title': 'Candy Alley',
  'park.alley.hint': 'Fair treats! Snacks land in Gooby\u2019s food tray.',
  'park.stall.cottonCandy.name': 'Sugar Cloud',
  'park.stall.softServe.name': 'Swirl Stop',
  'park.stall.waffle.name': 'Waffle Wonder',
  'park.stall.cottonCandy.pitch': 'A pink cloud on a stick \u2014 pure fair magic.',
  'park.stall.softServe.pitch': 'A creamy swirl with a cone hat.',
  'park.stall.waffle.pitch': 'Fresh off the iron, golden and warm.',

  // ---- E2: Funkelpark coaster captions (park.coaster.*, labeled block) ----
  // (delivered via /tmp/gooby-v6-handoffs/E2-strings-for-E3.txt — verbatim)
  'park.coaster.name': 'Sparkle Loop',
  'park.coaster.board': 'All aboard! Gooby hops into the front cart.',
  'park.coaster.lift': 'Clank\u2026 clank\u2026 up, up, up\u2026',
  'park.coaster.drop': 'Hold on tiiight!',
  'park.coaster.loop': 'Loop-the-loop! Wheee!',
  'park.coaster.photo': 'Say cheese!',
  'park.coaster.hills': 'Bunny hops! Boing, boing.',
  'park.coaster.brake': 'Aaand\u2026 breathe out.',
  'park.coaster.done': 'What a ride! Gooby is still wobbly.',
  'park.coaster.handsUpHint': 'Hold anywhere: hands up!',
  'park.coaster.photoSaved': 'Ride photo saved to your album!',
  // ---- end E2 coaster captions ----

  // ---- F4: Riesenrad — the calm wheel ride (park.wheel.*, labeled block) ----
  'park.wheel.name': 'Giant Wheel',
  'park.wheel.confirm.title': 'A calm round?',
  'park.wheel.confirm.body': 'Float up over Funkelpark \u2014 one gentle spin on the Giant Wheel.',
  'park.wheel.confirm.go': 'Hop in',
  'park.wheel.board': 'Gooby snuggles into a pastel gondola.',
  'park.wheel.apex': 'The very top! Gooby waves at the whole park.',
  'park.wheel.done': 'Back down \u2014 what a lovely view that was.',
  'park.wheel.skipHint': 'Tap to come back down',
  'park.wheel.photoSaved': 'View photo saved to your album!',
  // ---- end F4 wheel strings ----
};

/** @type {Record<string, string>} */
export const DE = {
  // --- park foods (data/foods.js V6_PARK_FOODS nameKeys) ---
  'food.cottonCandy': 'Zuckerwatte',
  'food.softServe': 'Softeis',
  'food.waffle': 'Waffel',

  // --- Candy Alley stall sheet + signage (E3) ---
  'park.alley.title': 'Naschgasse',
  'park.alley.hint': 'Jahrmarkt-Leckereien! Snacks landen in Goobys Futter-Tablett.',
  'park.stall.cottonCandy.name': 'Zuckerwolke',
  'park.stall.softServe.name': 'Eiswirbel',
  'park.stall.waffle.name': 'Waffelzauber',
  'park.stall.cottonCandy.pitch': 'Eine rosa Wolke am Stiel \u2014 pure Jahrmarktmagie.',
  'park.stall.softServe.pitch': 'Cremiger Wirbel mit Waffelh\u00fctchen.',
  'park.stall.waffle.pitch': 'Frisch vom Eisen, goldig und warm.',

  // ---- E2: Funkelpark coaster captions (park.coaster.*, labeled block) ----
  // (delivered via /tmp/gooby-v6-handoffs/E2-strings-for-E3.txt — verbatim)
  'park.coaster.name': 'Funkel-Looping',
  'park.coaster.board': 'Einsteigen bitte! Gooby h\u00fcpft in den vorderen Wagen.',
  'park.coaster.lift': 'Klack\u2026 klack\u2026 hoch, hoch, hoch\u2026',
  'park.coaster.drop': 'Guuut festhalten!',
  'park.coaster.loop': 'Looping! Juchhuu!',
  'park.coaster.photo': 'Bitte l\u00e4cheln!',
  'park.coaster.hills': 'H\u00fcgelh\u00fcpfer! Boing, boing.',
  'park.coaster.brake': 'Uuund\u2026 ausatmen.',
  'park.coaster.done': 'Was f\u00fcr eine Fahrt! Gooby zittert noch.',
  'park.coaster.handsUpHint': '\u00dcberall halten: H\u00e4nde hoch!',
  'park.coaster.photoSaved': 'Fahrtfoto in deinem Album gespeichert!',
  // ---- end E2 coaster captions ----

  // ---- F4: Riesenrad — the calm wheel ride (park.wheel.*, labeled block) ----
  'park.wheel.name': 'Riesenrad',
  'park.wheel.confirm.title': 'Eine ruhige Runde?',
  'park.wheel.confirm.body': 'Schweb hoch \u00fcber den Funkelpark \u2014 eine sanfte Runde im Riesenrad.',
  'park.wheel.confirm.go': 'Einsteigen',
  'park.wheel.board': 'Gooby kuschelt sich in eine Pastell-Gondel.',
  'park.wheel.apex': 'Ganz oben! Gooby winkt dem ganzen Park zu.',
  'park.wheel.done': 'Wieder unten \u2014 was f\u00fcr eine sch\u00f6ne Aussicht.',
  'park.wheel.skipHint': 'Tippen zum Runterfahren',
  'park.wheel.photoSaved': 'Aussichtsfoto in deinem Album gespeichert!',
  // ---- end F4 wheel strings ----
};
