import { id, nowIso } from './util.js';
import { applyBingoAppEvent } from './game-rules.js';

/**
 * App-Event-Log (v3.0) — die gemeinsame Meilenstein-/Ereignis-API.
 *
 * ── Abstimmung zwischen den 3.0-Agents ────────────────────────────────────
 * Agent A (Rituale & Beziehung) LEGT dieses Modul AN und emittiert die unten
 * dokumentierten Ereignisse. Agent C (Level/Badges) KONSUMIERT sie:
 *
 *   1. Historisch:  GET /api/app-events?limit=…&type=…  (neueste zuerst,
 *      registriert in rituals.js) — ideal, um beim App-Start XP/Badges
 *      nachzuziehen.
 *   2. Live:        WS-Broadcast `app_event { event }` an beide Partner.
 *   3. Eigene Ereignisse emittieren: einfach `emitAppEvent()` importieren
 *      und mit einem neuen `type` aufrufen — bitte Typen hier dokumentieren.
 *
 * Event-Objekt: { id: "ae_…", type, memberId, data: {…}, createdAt }
 * `memberId` = wer das Ereignis ausgelöst hat (null bei Paar-Ereignissen,
 * die niemand einzelnes ausgelöst hat). `data` ist ein kleines JSON-Objekt
 * mit Kontext (ids, Prozentwerte …) — KEINE großen Payloads.
 *
 * ── Von Agent A emittierte Typen (Stand 3.0) ──────────────────────────────
 *   daymemo_first        { dateKey }             erster Audio-Check-in des Paares
 *   daymemo_both         { dateKey }             beide haben an einem Tag aufgenommen
 *   capsule_sealed       { capsuleId, unlockAt } Zeitkapsel versiegelt
 *   capsule_opened       { capsuleId }           Zeitkapsel geöffnet (Zeremonie)
 *   need_sent            { needId, needType }    Bedürfnis-Knopf gedrückt
 *   goal_created         { goalId }              gemeinsames Ziel angelegt
 *   goal_milestone       { goalId, percent }     25/50/75-%-Meilenstein überschritten
 *   goal_reached         { goalId }              Ziel zu 100 % erreicht
 *   weekplan_slot_created{ slotId, kind }        Wochenplan-Slot (z. B. Telefon-Date) angelegt
 *   magazine_seen_both   { month }               beide haben eine Monats-Ausgabe gelesen
 *
 * ── Von Agent B (Spiele) emittierte Typen (Stand 3.0, router.js) ───────────
 *   movie_match          { gameId, cardIndex, title }  Film-Roulette: beide nach
 *                        rechts gewischt (memberId = null, gehört beiden) —
 *                        der Wochenplan macht daraus einen Filmabend-Vorschlag.
 *                        Seit 3.0.1 SERVER-SEITIG aus den gespeicherten Moves
 *                        abgeleitet (beide Likes müssen existieren).
 *   quest_done           { gameId, dateKey, questIndex } Paar-Tagesquest
 *                        abgehakt (memberId = wer abgehakt hat). Seit 3.0.1
 *                        idempotent pro (dateKey, questIndex).
 *
 * ── Von Agent C (Plattform) emittierte Typen (Stand 3.0, platform.js) ──────
 *   icon_gift_sent       { icon }                App-Icon verschenkt
 *   datenight_planned    { dateNightId }         Date-Night angesetzt
 *
 * Kapazität: die letzten 500 Ereignisse pro Paar (älteste fallen raus) —
 * Konsumenten sollten abgeleitete Zustände (XP, Badges) selbst persistieren.
 *
 * ── Idempotenz (3.0.1) ─────────────────────────────────────────────────────
 * `emitAppEvent` nimmt optional einen `dedupeKey`. Pro Paar wird ein
 * persistenter Schlüsselindex (`couple.appEventKeys`, gedeckelt) geführt:
 * derselbe (type, dedupeKey) emittiert GENAU EINMAL — auch über Restarts und
 * über das Ring-Buffer-Limit hinaus. Replays/Duplikate liefern `null` zurück
 * und erzeugen weder Broadcast noch XP (gamification konsumiert nur
 * gespeicherte Events).
 */

const APP_EVENTS_CAP = 500;
const APP_EVENT_KEYS_CAP = 2000;

/**
 * Canonical registry of every app-event type the server emits — the docs
 * contract test (server/test/events_contract.test.js) checks docs/API.md
 * against this list, so documentation can no longer drift from the code.
 */
export const APP_EVENT_TYPES = [
  'daymemo_first',
  'daymemo_both',
  'capsule_sealed',
  'capsule_opened',
  'need_sent',
  'goal_created',
  'goal_milestone',
  'goal_reached',
  'weekplan_slot_created',
  'magazine_seen_both',
  'movie_match',
  'quest_done',
  'icon_gift_sent',
  'datenight_planned',
  // v5.0 „Worte & Wärme"
  'goodthings_both',
  'thanks_sent',
  'missyou_sent',
  'dictionary_confirmed',
  'first_logged',
  // v5.0 season calendars
  'season_calendar_created',
  'season_calendar_door_opened',
  // v7.0 „Eure Woche" weekly review ritual
  'week_highlight_both',
  'week_review_both',
];

/** Error identifiers that are part of the documented event/ritual contract. */
export const APP_ERROR_CODES = Object.freeze({
  capsuleStillLocked: 'still_locked',
});

/** Lazily-defaulted event log on the couple (pre-v3.0 stores lack it). */
export function appEventsOf(couple) {
  if (!couple.appEvents) couple.appEvents = [];
  return couple.appEvents;
}

/**
 * Appends one app event, persists and broadcasts `app_event {event}` to the
 * whole couple. Returns the stored event — or `null` when `dedupeKey` is set
 * and the same (type, dedupeKey) was emitted before (replay protection).
 */
export function emitAppEvent({ store, realtime, couple, type, memberId = null, data = {}, dedupeKey = null }) {
  if (dedupeKey !== null) {
    if (!couple.appEventKeys) couple.appEventKeys = {};
    const key = `${type}|${dedupeKey}`;
    if (couple.appEventKeys[key]) return null;
    couple.appEventKeys[key] = nowIso();
    const keys = Object.keys(couple.appEventKeys);
    if (keys.length > APP_EVENT_KEYS_CAP) {
      keys.sort((x, y) => (couple.appEventKeys[x] < couple.appEventKeys[y] ? -1 : 1));
      for (const old of keys.slice(0, keys.length - APP_EVENT_KEYS_CAP)) delete couple.appEventKeys[old];
    }
  }
  const events = appEventsOf(couple);
  const event = { id: id('ae'), type, memberId, data, createdAt: nowIso() };
  events.push(event);
  if (events.length > APP_EVENTS_CAP) events.splice(0, events.length - APP_EVENTS_CAP);
  store.markDirty();
  realtime.broadcastCouple(couple.id, 'app_event', { event });
  for (const change of applyBingoAppEvent(couple, event)) {
    realtime.broadcastCouple(couple.id, 'game_move', {
      gameId: change.game.id,
      move: change.move,
    });
    if (change.ended) {
      realtime.broadcastCouple(couple.id, 'game_ended', { game: change.game });
    }
  }
  return event;
}
