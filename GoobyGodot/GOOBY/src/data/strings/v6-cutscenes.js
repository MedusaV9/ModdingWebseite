// V6/A1 — cutscene director strings (PLAN6 Wave A/A1) — OWNED BY THE
// CUTSCENE AGENT. Caption lines for authored scripts (data/cutscenes.js) and
// the shared cutscene chrome (tap-to-continue hint, hold/tap skip labels).
// Always EN + DE; the import + spread pair into data/strings.js is committed
// by A2 (this wave's strings.js owner — PLAN6 appendix rule). Until that
// lands, ui/cutsceneView.js resolves these through its local tx() fallback
// (G52 loading-veil pattern). No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // shared cutscene chrome
  'cutscene.tapContinue': 'Tap to continue',
  'cutscene.skipHold': 'Hold to skip',
  'cutscene.skipTap': 'Tap to skip',

  // demo script captions (data/cutscenes.js 'demo')
  'cutscene.demo.hello': 'Gooby waves hello!',
  'cutscene.demo.bye': 'See you around the house!',
};

/** @type {Record<string, string>} */
export const DE = {
  // shared cutscene chrome
  'cutscene.tapContinue': 'Tippen zum Weitermachen',
  'cutscene.skipHold': 'Halten zum Überspringen',
  'cutscene.skipTap': 'Tippen zum Überspringen',

  // demo script captions (data/cutscenes.js 'demo')
  'cutscene.demo.hello': 'Gooby winkt hallo!',
  'cutscene.demo.bye': 'Bis gleich im Haus!',
};
