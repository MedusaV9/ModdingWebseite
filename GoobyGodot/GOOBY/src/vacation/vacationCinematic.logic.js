// V6/D1 — vacation cinematic decision logic (PLAN6 Wave D/D1). PURE module —
// no DOM/three imports; node:test drives it directly
// (test/vacationCinematic.test.js). The view sibling
// (src/vacation/vacationCinematic.js) binds these decisions to
// ui/cutsceneView.js playCutscene.
//
// The two binding PLAN6 D1 contracts live HERE so they are headless-testable:
//
//   1. TRIGGER RULE (never-replay-on-boot): a vacation cutscene may start
//      ONLY from an explicit user action — the airport panel's book /
//      pick-up / pay-taxi taps (ui/airportScreen.js call sites). Phase
//      observation, boot catch-up, offline events, 'vacationChanged'
//      listeners etc. are NOT triggers: scriptForTrigger() answers null for
//      everything outside the frozen CINE_TRIGGERS table, so a departure can
//      never replay when a boot-time tick re-walks the same transitions.
//
//   2. ATOMICITY + OPTIONALITY (mutation-then-present): runMomentFlow() runs
//      the state mutation TO COMPLETION first and only then presents; a
//      refused (false) or throwing presentation NEVER changes the mutation's
//      result — cinema is always optional decoration on top of an already
//      committed transaction.

/** The three authored vacation scripts (ids in data/cutscenes.js). */
export const VAC_CINE_IDS = Object.freeze({
  departure: 'vacDeparture',
  reunionOnTime: 'vacReunionOnTime',
  reunionTaxi: 'vacReunionTaxi',
});

/**
 * The ONLY events allowed to start a vacation cutscene — each one is an
 * explicit airport-panel tap (PLAN6 D1: key off user actions, never phase
 * observation). Values map trigger → script id.
 * @type {Readonly<Record<string, string>>}
 */
export const CINE_TRIGGERS = Object.freeze({
  /** bookVacation returned ok (booking card tap). */
  book: VAC_CINE_IDS.departure,
  /** pickupVacation returned ok (free in-window pickup tap). */
  pickup: VAC_CINE_IDS.reunionOnTime,
  /** payTaxiReturn returned ok (overdue taxi tap). */
  taxi: VAC_CINE_IDS.reunionTaxi,
});

/**
 * Pick the script for a completed vacation action. Fails CLOSED: unknown
 * triggers (including anything a phase observer might invent — 'boot',
 * 'offline', 'vacationChanged', …) and non-ok results answer null, which
 * callers treat as "no cinema" (the flow already finished either way).
 * @param {string} trigger CINE_TRIGGERS key ('book' | 'pickup' | 'taxi')
 * @param {{ok?: boolean}|null|undefined} result the COMPLETED economy result
 * @returns {string|null} data/cutscenes.js id or null
 */
export function scriptForTrigger(trigger, result) {
  if (result == null || typeof result !== 'object' || result.ok !== true) return null;
  return CINE_TRIGGERS[trigger] ?? null;
}

/**
 * The mutation-then-present flow contract (PLAN6 D1 acceptance): `mutate`
 * runs synchronously TO COMPLETION first — the payment/pickup state
 * transition is fully committed before any presentation starts. `present`
 * runs strictly afterwards and ONLY for an ok mutation; it may return false
 * (refused — camera busy, wrong scene, reduced environments) or throw, and
 * neither changes the flow outcome: the mutation result passes through
 * verbatim, only `presented` reports whether the decoration actually played.
 * @param {{
 *   mutate: () => {ok?: boolean}|null|undefined,
 *   present: (result: object) => boolean|Promise<boolean>,
 * }} flow
 * @returns {Promise<{result: object|null, presented: boolean}>}
 */
export async function runMomentFlow({ mutate, present }) {
  const result = mutate() ?? null;
  if (result?.ok !== true) return { result, presented: false };
  let presented = false;
  try {
    presented = (await present(result)) === true;
  } catch {
    presented = false; // cinema is decoration — failures stay silent
  }
  return { result, presented };
}

/**
 * Parse the dev `?vacationcine=` harness value (§E9 spirit — the QA surface
 * for the three set pieces). Pure so the table stays node-testable:
 *   departure     → seed a booked-away slice (post-mutation state), then
 *                   present through the 'book' trigger
 *   reunionOnTime → present through 'pickup' (Gooby already home)
 *   reunionTaxi   → present through 'taxi'
 * Unknown/junk values answer null (harness params are forgiving).
 * @param {string|null|undefined} value raw query-param value
 * @returns {{trigger: string, seedAway: boolean}|null}
 */
export function harnessKickFor(value) {
  switch (value) {
    case 'departure': return { trigger: 'book', seedAway: true };
    case 'reunionOnTime': return { trigger: 'pickup', seedAway: false };
    case 'reunionTaxi': return { trigger: 'taxi', seedAway: false };
    default: return null;
  }
}
