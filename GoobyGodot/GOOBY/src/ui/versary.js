// V6.1/G3 (FINAL-WAVE B5) — the Gooby-versary quiet-home poll: fires the
// authored versaryMonth (save age ≥ 30 days) / versaryYear (≥ 365 days) home
// cutscenes once ever. NO new save keys — due-ness derives from the save's
// existing `createdAt` stamp and once-ever from the existing cutscene `seen`
// slice (playCutscene latches seen BEFORE playback, so an interrupted first
// view still never re-fires).
//
// Two layers, mirroring ui/whatsNew.js:
//  1. PURE exports up top (VERSARY numbers, the versaryDue() selector and
//     the G3 fallback dictionaries) — no DOM/three imports, covered by
//     test/versary.test.js.
//  2. Browser driver initVersary() — a quiet-home interval poll (whatsNew.js
//     boot-poll pattern) that only kicks the cutscene when the player is
//     home, unswitched, awake, with no screen/panel up and no other cutscene
//     active. playCutscene() re-checks the same lease conditions internally
//     (and refuses when busy), so a race just retries on a later poll.
//
// §E0.1-2: every exact number is a frozen const INSIDE this owning module.

import { hasSeen } from '../systems/cutscene.js';
import { isSleeping } from '../systems/sleep.js';

// ---------------------------------------------------------------------------
// Pure logic (covered by test/versary.test.js)
// ---------------------------------------------------------------------------

/** §E0.1-2: the binding versary numbers — frozen here. */
export const VERSARY = Object.freeze({
  /** One real day in ms (fixed 24 h — the postcards.js DAY_MS convention). */
  DAY_MS: 86400000,
  /** The one-month moment fires at save age ≥ this many days. */
  MONTH_DAYS: 30,
  /** The one-year moment fires at save age ≥ this many days. */
  YEAR_DAYS: 365,
  /** Quiet-home poll cadence (ms) — deliberately slower than whatsNew's
   * 400 ms so every one-time veteran panel wins the first quiet slot. */
  POLL_MS: 1500,
});

/**
 * Which versary cutscene (if any) is due for this save right now?
 * Junk-hostile: a missing/non-finite/non-positive createdAt never fires, and
 * a FUTURE createdAt (clock rollback / hostile save) yields a negative age
 * and never fires either. When both moments are overdue (e.g. a 400-day-old
 * save that never got a quiet home slot) the MONTH plays first — the year
 * becomes due on a later poll once the month is in the seen map. Each id is
 * suppressed forever once seen (the existing cutscene seen slice; no new
 * save keys).
 * @param {object} state save state ({createdAt, cutscenes?} shape)
 * @param {number} nowMs current epoch ms
 * @returns {'versaryMonth'|'versaryYear'|null}
 */
export function versaryDue(state, nowMs) {
  const createdAt = Number(state?.createdAt);
  if (!Number.isFinite(createdAt) || createdAt <= 0) return null;
  const ageDays = (Number(nowMs) - createdAt) / VERSARY.DAY_MS;
  if (!Number.isFinite(ageDays) || ageDays < 0) return null;
  if (ageDays >= VERSARY.MONTH_DAYS && !hasSeen(state, 'versaryMonth')) {
    return 'versaryMonth';
  }
  if (ageDays >= VERSARY.YEAR_DAYS && !hasSeen(state, 'versaryYear')) {
    return 'versaryYear';
  }
  return null;
}

// ---------------------------------------------------------------------------
// G3 fallback dictionaries (FINAL-WAVE handoff: the canonical entries live
// with G1 — /tmp/gooby-v6-handoffs/G3-strings-manifest.txt. main.js merges
// these into the RUNTIME dicts additively, existing keys always win, so the
// keys resolve through plain t() everywhere until G1's merge lands and
// silently defer to it afterwards.)
// ---------------------------------------------------------------------------

/** @type {Record<string, string>} */
export const VERSARY_EN = Object.freeze({
  // B5 — versary cutscene captions
  'cutscene.versary.month.title': 'One whole month of Gooby and you!',
  'cutscene.versary.month.dance': 'Gooby does his happiest bounce, just for you.',
  'cutscene.versary.month.thanks': 'Thank you for every single day.',
  'cutscene.versary.year.title': 'A whole YEAR of Gooby and you!',
  'cutscene.versary.year.memories': 'So many naps, snacks and little adventures…',
  'cutscene.versary.year.confetti': 'Gooby jumps so high the confetti joins in!',
  'cutscene.versary.year.thanks': 'Here is to many more days together.',
  // B3 — postcard pool variants 4/5 (POSTCARDS.VARIANTS is 5 now)
  'vacation.postcard.beach.4': 'I found a shell that whispers the sea!',
  'vacation.postcard.beach.5': 'I buried my feet in the sand. Then I forgot where.',
  'vacation.postcard.meadowTrip.4': 'A butterfly used my ear as a bench!',
  'vacation.postcard.meadowTrip.5': 'The grass tickles. I giggled at a whole field.',
  'vacation.postcard.bigCity.4': 'I found a fountain and made a BIG wish!',
  'vacation.postcard.bigCity.5': 'The pigeons here walk very importantly. Me too now.',
  'vacation.postcard.space.4': 'The moon is very round. We are basically twins!',
  'vacation.postcard.space.5': 'I tried to nap but kept drifting off the bed!',
  'vacation.postcard.harbor.4': 'A little tugboat tooted hello at me!',
  'vacation.postcard.harbor.5': 'The lighthouse blinks slow. I blink back slower.',
  'vacation.postcard.spookGarden.4': 'A friendly bat showed me how to hang upside down!',
  'vacation.postcard.spookGarden.5': 'The fog is soft like a blanket. I tried to fold it.',
  'vacation.postcard.bakery.4': 'I sniffed the croissants until I got dizzy!',
  'vacation.postcard.bakery.5': 'Flour makes a very good pillow. Very dusty too.',
  'vacation.postcard.nightSky.4': 'The clouds below look like sheep. I counted four.',
  'vacation.postcard.nightSky.5': 'I told the moon about you. It smiled, I think.',
  'vacation.postcard.toyRoom.4': 'The marble run goes clickety-click. I watched it forever!',
  'vacation.postcard.toyRoom.5': 'I won at cards against the teddy. He is a good sport.',
  // B6 — ride-photo polaroid strip + viewer chip (proper noun, both langs)
  'gallery.frame.park': 'Funkelpark',
  // B8 — night apex caption (shown instead of park.wheel.apex at night)
  'park.wheel.apexNight': 'The very top! The whole park twinkles below like spilled stars.',
  // B1 — settings love note ({heart} → authored glyph in settingsScreen.js)
  'settings.loveNote': 'made with {heart} for you and Gooby',
});

/** @type {Record<string, string>} */
export const VERSARY_DE = Object.freeze({
  // B5 — Versary-Untertitel
  'cutscene.versary.month.title': 'Ein ganzer Monat Gooby und du!',
  'cutscene.versary.month.dance': 'Gooby macht seinen fröhlichsten Hüpfer, nur für dich.',
  'cutscene.versary.month.thanks': 'Danke für jeden einzelnen Tag.',
  'cutscene.versary.year.title': 'Ein ganzes JAHR Gooby und du!',
  'cutscene.versary.year.memories': 'So viele Nickerchen, Snacks und kleine Abenteuer…',
  'cutscene.versary.year.confetti': 'Gooby springt so hoch, dass das Konfetti mitfeiert!',
  'cutscene.versary.year.thanks': 'Auf viele weitere gemeinsame Tage.',
  // B3 — Postkarten-Varianten 4/5
  'vacation.postcard.beach.4': 'Ich habe eine Muschel gefunden, die das Meer flüstert!',
  'vacation.postcard.beach.5': 'Ich habe meine Füße im Sand vergraben. Dann hab ich vergessen wo.',
  'vacation.postcard.meadowTrip.4': 'Ein Schmetterling hat mein Ohr als Bank benutzt!',
  'vacation.postcard.meadowTrip.5': 'Das Gras kitzelt. Ich habe eine ganze Wiese angekichert.',
  'vacation.postcard.bigCity.4': 'Ich habe einen Brunnen gefunden und mir GROSS was gewünscht!',
  'vacation.postcard.bigCity.5': 'Die Tauben hier laufen sehr wichtig herum. Ich jetzt auch.',
  'vacation.postcard.space.4': 'Der Mond ist sehr rund. Wir sind quasi Zwillinge!',
  'vacation.postcard.space.5': 'Ich wollte schlafen, bin aber immer vom Bett weggeschwebt!',
  'vacation.postcard.harbor.4': 'Ein kleiner Schlepper hat mir Hallo getutet!',
  'vacation.postcard.harbor.5': 'Der Leuchtturm blinkt langsam. Ich blinzle noch langsamer zurück.',
  'vacation.postcard.spookGarden.4': 'Eine nette Fledermaus hat mir gezeigt, wie man kopfüber hängt!',
  'vacation.postcard.spookGarden.5': 'Der Nebel ist weich wie eine Decke. Ich wollte ihn falten.',
  'vacation.postcard.bakery.4': 'Ich habe an den Croissants geschnuppert, bis mir schwindelig war!',
  'vacation.postcard.bakery.5': 'Mehl ist ein sehr gutes Kissen. Aber auch sehr staubig.',
  'vacation.postcard.nightSky.4': 'Die Wolken da unten sehen aus wie Schafe. Ich habe vier gezählt.',
  'vacation.postcard.nightSky.5': 'Ich habe dem Mond von dir erzählt. Er hat gelächelt, glaube ich.',
  'vacation.postcard.toyRoom.4': 'Die Murmelbahn macht klick-klack. Ich habe ewig zugeschaut!',
  'vacation.postcard.toyRoom.5': 'Ich habe beim Kartenspiel gegen den Teddy gewonnen. Er ist ein guter Verlierer.',
  // B6 — Polaroid-Streifen + Viewer-Chip (Eigenname, beide Sprachen)
  'gallery.frame.park': 'Funkelpark',
  // B8 — Nacht-Scheitelpunkt
  'park.wheel.apexNight': 'Ganz oben! Der ganze Park funkelt unten wie verschüttete Sterne.',
  // B1 — Settings-Liebesnotiz
  'settings.loveNote': 'mit {heart} gemacht — für dich und Gooby',
});

// ---------------------------------------------------------------------------
// Browser driver
// ---------------------------------------------------------------------------

/**
 * Arm the quiet-home versary poll (main.js V6.1/G3 marked block). All
 * side-effectful collaborators arrive injected so the module root stays
 * headless-importable (whatsNew.js layering).
 * @param {{
 *   store: {get: () => object},
 *   ui: {activeScreenId?: () => string|null},
 *   sceneManager: {currentId: () => string|null, isSwitching?: () => boolean},
 *   playCutscene: (id: string) => Promise<boolean>,
 *   isCutsceneActive?: () => boolean,
 *   nowFn?: () => number,
 * }} deps
 * @returns {() => void} stop() — clears the poll (tests/HMR)
 */
export function initVersary({
  store, ui, sceneManager, playCutscene, isCutsceneActive, nowFn = Date.now,
}) {
  let inFlight = false;
  const poll = setInterval(() => {
    if (inFlight) return;
    const state = store.get();
    const due = versaryDue(state, nowFn());
    if (!due) {
      // Both moments seen → nothing can ever become due again; stand down.
      if (hasSeen(state, 'versaryMonth') && hasSeen(state, 'versaryYear')) {
        clearInterval(poll);
      }
      return;
    }
    // The quiet-home gate (whatsNew.js pattern): home, unswitched, awake,
    // no screen, no sheet, no other cinematic.
    if (sceneManager?.currentId?.() !== 'home') return;
    if (sceneManager?.isSwitching?.()) return;
    if (isSleeping(state)) return;
    if (ui?.activeScreenId?.()) return;
    if (typeof document !== 'undefined' && document.querySelector('.panel-backdrop')) return;
    if (isCutsceneActive?.()) return;
    inFlight = true;
    // playCutscene re-checks the camera lease and latches seen on success;
    // a refusal (returns false) simply waits for a later, quieter poll.
    Promise.resolve(playCutscene(due))
      .catch(() => false)
      .finally(() => { inFlight = false; });
  }, VERSARY.POLL_MS);
  return () => clearInterval(poll);
}
