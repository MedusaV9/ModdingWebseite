// V6/D1 — vacation cinematic presenter (PLAN6 Wave D/D1): the thin
// vacation-specific driver between ui/airportScreen.js's explicit user
// actions and the Wave-A cutscene stack (systems/cutscene.js pure director +
// ui/cutsceneView.js view driver + data/cutscenes.js scripts). This module
// adds NO new engine — it only:
//
//   1. picks the script through the PURE sibling
//      (vacationCinematic.logic.js scriptForTrigger — the never-replay-on-
//      boot trigger table lives there, headless-tested);
//   2. hard-guarantees the D1 atomicity contract at the seam: it is only
//      ever handed a COMPLETED economy result (bookVacation /
//      pickupVacation / payTaxiReturn already returned ok before this
//      module runs), never mutates vacation/payment state itself, and
//      treats every refused/false/thrown presentation as "skip silently" —
//      cinema is ALWAYS optional decoration;
//   3. stage-manages the one vacation-specific quirk the generic driver
//      cannot know: the departure plays AFTER booking committed, so
//      home/interactions.js has already hidden the rig
//      (gooby.group.visible=false on 'vacationChanged'). The presenter
//      lifts visibility for the send-off performance and re-syncs it from
//      the CURRENT slice in `finally`, so every exit path (finished,
//      skipped, refused, thrown) lands on the exact state the visibility
//      sync would produce.
//
// Dev harness (§E9, dev builds only): ?vacationcine=departure|reunionOnTime|
// reunionTaxi stages one set piece after boot (departure seeds a booked
// slice first — mutation-then-present, via the same runMomentFlow contract).
// Listed in data/harnessParams.js (card 18); armed from the V6/D1 marked
// block in ui/airportScreen.js registerAirport.

import { EN as SCENE_EN, DE as SCENE_DE } from '../data/strings/v6-vacation-scenes.js';
import { EN as GLOBAL_EN, DE as GLOBAL_DE } from '../data/strings.js';
import { playCutscene } from '../ui/cutsceneView.js';
import { getGooby } from '../home/homeScene.js';
import { isAway, bookSlice, VACATION_PHASE } from '../systems/vacation.js';
import { now } from '../core/clock.js';
import { scriptForTrigger, runMomentFlow, harnessKickFor } from './vacationCinematic.logic.js';

// §E0.1-2: presenter-local numbers — frozen in the owning module.
const PRESENT = Object.freeze({
  /** Bounded refusal retries: a REFUSED playCutscene (camera lease busy —
   * e.g. the boot fade or a room pan still in flight when the user taps
   * fast) is re-attempted a few times before giving up silently. Every
   * retry re-runs the full lease checks, so a late attempt can only ever
   * start on the quiet home scene. Throws are NEVER retried. */
  REFUSAL_RETRIES: 4,
  REFUSAL_DELAY_MS: 700,
  /** Dev ?vacationcine= kick retry cadence/budget (cutsceneView parity —
   * playCutscene refuses until the home scene + camera lease are live). */
  DEV_KICK_DELAY_MS: 900,
  DEV_KICK_RETRIES: 12,
});

/** Dev-only breadcrumbs (cutsceneView pattern) — stripped from prod builds. */
const DEV = !!import.meta.env?.DEV;

let stringsBridged = false;

/**
 * Same-wave i18n bridge: D2 owns strings.js in Wave D and commits the
 * v6-vacation-scenes import pair (handoff D1-strings-import.txt). Until that
 * lands, ui/cutsceneView.js resolves caption keys through t() — so spread
 * the owned module into the LIVE dictionaries once at runtime (browser
 * only; node tests import the module directly). Idempotent, and a no-op
 * re-set of identical values after D2's import merges.
 */
function bridgeStrings() {
  if (stringsBridged) return;
  stringsBridged = true;
  Object.assign(GLOBAL_EN, SCENE_EN);
  Object.assign(GLOBAL_DE, SCENE_DE);
}

/**
 * Present the vacation cutscene for a COMPLETED airport action. Never
 * mutates vacation/payment state; never throws; resolves false whenever the
 * cinema was refused or failed (callers continue silently — the underlying
 * transaction already committed before this was called).
 * @param {{store: object}} deps store handle (visibility re-sync source)
 * @param {string} trigger 'book' | 'pickup' | 'taxi' (logic.js table)
 * @param {{ok?: boolean}} result the completed economy result
 * @returns {Promise<boolean>} true only when the cutscene actually played
 */
export async function presentVacationCinematic(deps, trigger, result) {
  const id = scriptForTrigger(trigger, result);
  if (!id) return false;
  bridgeStrings();
  // The send-off performance: booking already hid the rig
  // (home/interactions.js syncs gooby.group.visible on 'vacationChanged'
  // AND on every coalesced 'change' — e.g. the seen-slice write inside
  // playCutscene re-triggers it mid-playback). A one-shot lift is not
  // enough, so a per-frame keeper re-asserts visibility for the bounded
  // presentation window (no store subscription — the presenter must never
  // observe state, see the never-replay rule). The home handles may not be
  // live yet during a boot fade, hence the fresh getGooby() per frame.
  let keeperRaf = 0;
  const keepVisible = () => {
    const gooby = getGooby();
    if (gooby?.group) gooby.group.visible = true;
    keeperRaf = requestAnimationFrame(keepVisible);
  };
  try {
    keepVisible();
    let played = await playCutscene(id);
    // Refusals (boot fade / room pan still in flight under a fast tap) get
    // a few bounded re-attempts — each re-runs every lease check, and the
    // final refusal still falls through silently.
    for (let retry = 0; played !== true && retry < PRESENT.REFUSAL_RETRIES; retry += 1) {
      await new Promise((resolve) => setTimeout(resolve, PRESENT.REFUSAL_DELAY_MS));
      played = await playCutscene(id);
    }
    return played === true;
  } catch (err) {
    console.warn(`[vacationCine] '${id}' presentation failed (flow continues):`, err);
    return false;
  } finally {
    cancelAnimationFrame(keeperRaf);
    // Re-sync from the CURRENT slice — never from a snapshot — so every
    // exit path (finished/skipped/refused/thrown) matches the state
    // home/interactions.js's visibility sync would produce.
    try {
      const gooby = getGooby();
      if (gooby?.group) gooby.group.visible = !isAway(deps?.store?.get?.());
    } catch (err) {
      console.warn('[vacationCine] visibility re-sync failed:', err);
    }
  }
}

/**
 * Arm the dev `?vacationcine=` harness (dev builds only). Called from the
 * V6/D1 marked block in ui/airportScreen.js registerAirport (idempotent —
 * re-registration is a no-op via the module-level latch). Retries while the
 * boot fade/pan settles, then gives up quietly (§E9 patience — cutsceneView
 * dev-kick parity).
 * @param {{store: object, ui: object}} deps
 */
let harnessArmed = false;
export function initVacationCinematicHarness(deps) {
  if (harnessArmed) return;
  harnessArmed = true;
  bridgeStrings();
  const param = DEV && typeof location !== 'undefined'
    ? new URLSearchParams(location.search).get('vacationcine')
    : null;
  const kick = harnessKickFor(param);
  if (!kick) {
    if (param) console.warn(`[vacationCine] ?vacationcine=${param} — unknown value`);
    return;
  }
  const { store } = deps;
  let tries = 0;
  const attempt = () => {
    runMomentFlow({
      // mutation-then-present even in the harness: the departure kick seeds
      // the booked-away slice BEFORE any presentation (the reunion kicks
      // present over the already-home state, mirroring a completed pickup).
      mutate: () => {
        if (kick.seedAway && !isAway(store.get())) {
          store.update((state) => {
            state.vacation = bookSlice(state.vacation, 'beach', now());
          });
          store.emit?.('vacationChanged', { phase: VACATION_PHASE.AWAY, destId: 'beach' });
        }
        return { ok: true };
      },
      present: () => presentVacationCinematic(deps, kick.trigger, { ok: true }),
    }).then(({ presented }) => {
      if (presented) return;
      tries += 1;
      if (tries < PRESENT.DEV_KICK_RETRIES) setTimeout(attempt, PRESENT.DEV_KICK_DELAY_MS);
      else console.warn(`[vacationCine] ?vacationcine=${param} gave up after ${tries} busy retries`);
    });
  };
  setTimeout(attempt, PRESENT.DEV_KICK_DELAY_MS);
}
