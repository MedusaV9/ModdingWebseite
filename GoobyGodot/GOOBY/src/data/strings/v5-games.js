// V5/G06: v5-games.js (PLAN5 §V5 — the 5.0 minigame wave) — OWNED BY AGENT
// V5/G06. Strings for the two new comfy games: Tea Party („Teestube", §V5.1,
// games/teaParty.js) and Hide & Seek („Guck-guck-Garten", §V5.2,
// games/hideSeek.js) — arcade-tile titles + in-game banners/floaters.
// Always EN + DE. No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  'mg.title.teaParty': 'Tea Party',
  'mg.tea.perfect': 'Perfect!',
  'mg.tea.good': 'Nice pour',
  'mg.tea.overflow': 'Overflow!',
  'mg.tea.miss': 'Spilled…',
  'mg.tea.streak': '{n} perfect cups! +{b}',
  'mg.tea.spills': 'Spill {n}/{max}',

  'mg.title.hideSeek': 'Peekaboo Garden',
  'mg.seek.found': 'Found!',
  'mg.seek.empty': 'Nobody here…',
  'mg.seek.waveClear': 'All found! +{n}',
  'mg.seek.waveNew': '{n} friends are hiding…',
  'mg.seek.expired': 'They re-hid themselves!',
};

/** @type {Record<string, string>} */
export const DE = {
  'mg.title.teaParty': 'Teestube',
  'mg.tea.perfect': 'Perfekt!',
  'mg.tea.good': 'Gut eingeschenkt',
  'mg.tea.overflow': 'Übergelaufen!',
  'mg.tea.miss': 'Verschüttet…',
  'mg.tea.streak': '{n} perfekte Tassen! +{b}',
  'mg.tea.spills': 'Patzer {n}/{max}',

  'mg.title.hideSeek': 'Guck-guck-Garten',
  'mg.seek.found': 'Gefunden!',
  'mg.seek.empty': 'Hier ist niemand…',
  'mg.seek.waveClear': 'Alle gefunden! +{n}',
  'mg.seek.waveNew': '{n} Freunde verstecken sich…',
  'mg.seek.expired': 'Sie haben sich neu versteckt!',
};
