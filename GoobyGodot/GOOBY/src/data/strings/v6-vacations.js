// V6/B2 — nine-destination travel board strings (PLAN6 Wave B) — OWNED BY
// AGENT B2. The five new recap-place destinations (harbor, spookGarden,
// bakery, nightSky, toyRoom): airport cards, postcards, and the locked
// mystery-card presentation ('???' + lock + level hint — same language as
// the V5 mystery sticker slots). Always EN + DE; spread into
// data/strings.js AFTER the v6-cutscenes module. No other agent may edit
// this module.

/** @type {Record<string, string>} */
export const EN = {
  // destination cards (vacation.dest.<id>.name / .sub — v5-vacation shape)
  'vacation.dest.harbor.name': 'Harbor Cruise',
  'vacation.dest.harbor.sub': 'Boats, gulls and salty breezes',
  'vacation.dest.spookGarden.name': 'Haunted Garden',
  'vacation.dest.spookGarden.sub': 'Friendly ghosts and glowing gourds',
  'vacation.dest.bakery.name': 'Bakery Weekend',
  'vacation.dest.bakery.sub': 'Warm bread and sugar dust',
  'vacation.dest.nightSky.name': 'Night Sky',
  'vacation.dest.nightSky.sub': 'A balloon ride among the stars',
  'vacation.dest.toyRoom.name': 'Toy Room',
  'vacation.dest.toyRoom.sub': 'A sleepover with the toys',

  // postcards (vacation.postcard.<id> — v5-vacation shape)
  'vacation.postcard.harbor': 'A gull shared my pretzel!!',
  'vacation.postcard.spookGarden': 'The ghosts giggle when I sneeze!',
  'vacation.postcard.bakery': 'I napped on a warm bread loaf…',
  'vacation.postcard.nightSky': 'I counted 100 stars, then lost count!!',
  'vacation.postcard.toyRoom': 'The toy robot is my best friend now!',

  // locked mystery cards (no name/sub/art disclosure before unlock)
  'vacation.dest.locked.name': '???',
  'vacation.dest.locked.sub': 'A new place awaits…',
  'vacation.dest.locked.hint': 'Reach level {level}',
};

/** @type {Record<string, string>} */
export const DE = {
  // destination cards (vacation.dest.<id>.name / .sub — v5-vacation shape)
  'vacation.dest.harbor.name': 'Hafen-Kreuzfahrt',
  'vacation.dest.harbor.sub': 'Boote, Möwen und salzige Brisen',
  'vacation.dest.spookGarden.name': 'Spukgarten',
  'vacation.dest.spookGarden.sub': 'Freundliche Geister und leuchtende Kürbisse',
  'vacation.dest.bakery.name': 'Bäckerei-Wochenende',
  'vacation.dest.bakery.sub': 'Warmes Brot und Zuckerstaub',
  'vacation.dest.nightSky.name': 'Nachthimmel',
  'vacation.dest.nightSky.sub': 'Eine Ballonfahrt zwischen den Sternen',
  'vacation.dest.toyRoom.name': 'Spielzeugzimmer',
  'vacation.dest.toyRoom.sub': 'Übernachtung bei den Spielsachen',

  // postcards (vacation.postcard.<id> — v5-vacation shape)
  'vacation.postcard.harbor': 'Eine Möwe hat meine Brezel geteilt!!',
  'vacation.postcard.spookGarden': 'Die Geister kichern, wenn ich niese!',
  'vacation.postcard.bakery': 'Ich habe auf einem warmen Brot geschlafen…',
  'vacation.postcard.nightSky': 'Ich habe 100 Sterne gezählt und mich dann verzählt!!',
  'vacation.postcard.toyRoom': 'Der Spielzeugroboter ist jetzt mein bester Freund!',

  // locked mystery cards (no name/sub/art disclosure before unlock)
  'vacation.dest.locked.name': '???',
  'vacation.dest.locked.sub': 'Ein neuer Ort wartet…',
  'vacation.dest.locked.hint': 'Erreiche Level {level}',
};
