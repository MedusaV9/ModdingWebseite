// V6/D1 — vacation cutscene captions (PLAN6 Wave D/D1) — OWNED BY THE
// VACATION-CINEMATIC AGENT. Caption beats for the three authored vacation
// set pieces in data/cutscenes.js ('vacDeparture', 'vacReunionOnTime',
// 'vacReunionTaxi'). Always EN + DE; the import + spread pair into
// data/strings.js is committed by D2 (this wave's strings.js owner — PLAN6
// appendix rule, see /tmp handoff D1-strings-import.txt). Until that lands,
// src/vacation/vacationCinematic.js bridges these keys into the live
// dictionaries at init so ui/cutsceneView.js's t() lookup already resolves
// them. No other agent may edit this module.
//
// NOTE: the cutscene 'caption' op renders keys through t(key) WITHOUT vars —
// every line here must read complete without interpolation.

/** @type {Record<string, string>} */
export const EN = {
  // vacDeparture — booking send-off (taxi + suitcase + sky-plane beats)
  'cutscene.vac.depart.taxi': 'The taxi is here — vacation time!',
  'cutscene.vac.depart.pack': 'Suitcase packed! Off on a big adventure!',
  'cutscene.vac.depart.wave': 'Bye-bye! Gooby waves goodbye!',
  'cutscene.vac.depart.sky': 'There he goes — up, up and away!',
  'cutscene.vac.depart.postcards': 'He will send postcards!',

  // vacReunionOnTime — punctual pickup reunion (hug + hearts + souvenir)
  'cutscene.vac.reunion.taxiBack': 'A taxi pulls up... someone is home!',
  'cutscene.vac.reunion.hug': 'Gooby missed you SO much!',
  'cutscene.vac.reunion.souvenir': 'His pockets are full of souvenir coins!',

  // vacReunionTaxi — late pickup, tired but warm (never punishing)
  'cutscene.vac.late.taxi': 'The taxi finally rolls in...',
  'cutscene.vac.late.phew': 'Phew... what a long ride home.',
  'cutscene.vac.late.warm': 'Sleepy — but SO happy to see you!',
  'cutscene.vac.late.souvenir': 'The souvenir coins made it home too!',
};

/** @type {Record<string, string>} */
export const DE = {
  // vacDeparture — booking send-off (taxi + suitcase + sky-plane beats)
  'cutscene.vac.depart.taxi': 'Das Taxi ist da — Urlaubszeit!',
  'cutscene.vac.depart.pack': 'Koffer gepackt! Auf ins große Abenteuer!',
  'cutscene.vac.depart.wave': 'Winke-winke! Gooby verabschiedet sich!',
  'cutscene.vac.depart.sky': 'Da fliegt er — hoch hinaus und davon!',
  'cutscene.vac.depart.postcards': 'Er schickt bestimmt Postkarten!',

  // vacReunionOnTime — punctual pickup reunion (hug + hearts + souvenir)
  'cutscene.vac.reunion.taxiBack': 'Ein Taxi fährt vor... da ist jemand wieder zu Hause!',
  'cutscene.vac.reunion.hug': 'Gooby hat dich SO sehr vermisst!',
  'cutscene.vac.reunion.souvenir': 'Seine Taschen sind voller Souvenir-Münzen!',

  // vacReunionTaxi — late pickup, tired but warm (never punishing)
  'cutscene.vac.late.taxi': 'Endlich rollt das Taxi heran...',
  'cutscene.vac.late.phew': 'Puh... was für eine lange Heimfahrt.',
  'cutscene.vac.late.warm': 'Müde — aber SO froh, dich zu sehen!',
  'cutscene.vac.late.souvenir': 'Die Souvenir-Münzen sind auch gut angekommen!',
};
