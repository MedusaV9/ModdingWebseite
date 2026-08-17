import { httpError, sendJson, nowIso, id, readJsonObject } from './util.js';
import { emitAppEvent } from './events.js';

/**
 * Plattform-Delights (v3.0, Agent C): App-Icon-Geschenke, Haptik-Duett und
 * Date-Night-Relay. Kleine Relay-Endpunkte ohne eigene Geschäftslogik-Tiefe —
 * der eigentliche Zauber (Auspack-Zeremonie, CoreHaptics, Live Activity)
 * passiert clientseitig.
 *
 * WS-Frames aus diesem Modul:
 *   icon_gift         { gift }                nur an den Beschenkten
 *   icon_gift_opened  { gift }                nur an den Schenkenden
 *   duet_start        { duet }                an beide (startAt = Serverzeit
 *                                             + Vorlauf; Clients rechnen mit
 *                                             ihrem Clock-Offset um)
 *   datenight_update  { dateNight | null }    an beide
 * Dazu relayt realtime.js `heartbeat_tap` Client→Partner (Live-Herzschlag).
 */

// Must match the alternate icons in ios/project.yml + GenerateIcon.swift.
export const ICON_IDS = [
  'classic',
  'sunset',
  'midnight',
  'mint',
  'rose',
  'ocean',
  'gold',
  'lavender',
  'blossom',
  'aurora',   // v10 — the tenth icon for the tenth version
];

const DUET_MAX_EVENTS = 64;
const DUET_LEAD_IN_MS = 2000;
const DATE_NIGHT_PHASES = ['anticipation', 'live', 'afterglow'];
const DATE_NIGHT_MAX_FUTURE_MS = 30 * 86_400_000;

/** Pending icon gifts keyed by RECIPIENT member id (pre-v3.0 stores lack it). */
function iconGiftsOf(couple) {
  if (!couple.iconGifts) couple.iconGifts = {};
  return couple.iconGifts;
}

export function registerPlatformRoutes(route, { asString, asEnum, partnerOf }) {
  // --- app-icon gifts ------------------------------------------------------

  // Gift an alternate app icon to the partner. Overwrites a still-unopened
  // gift (the newest surprise wins). The recipient learns about it via WS /
  // next fetch and gets the unwrap ceremony client-side.
  route('POST', '/api/icongift', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const icon = asEnum(body.icon, 'icon', ICON_IDS);
    const note = body.note != null ? asString(body.note, 'note', { max: 200, nonEmpty: false }) : null;
    const partner = partnerOf(c.auth.couple, c.auth.memberId);
    if (!partner) throw httpError(409, 'no_partner', 'Icon gifts need a partner');
    const gift = {
      id: id('ig'),
      icon,
      note,
      fromMemberId: c.auth.memberId,
      sentAt: nowIso(),
      openedAt: null,
    };
    iconGiftsOf(c.auth.couple)[partner.id] = gift;
    c.auth.couple.iconGiftsSent = (c.auth.couple.iconGiftsSent ?? 0) + 1; // badge: icon_gifted
    c.store.markDirty();
    c.realtime.sendToMember(c.auth.coupleId, partner.id, 'icon_gift', { gift });
    emitAppEvent({
      store: c.store,
      realtime: c.realtime,
      couple: c.auth.couple,
      type: 'icon_gift_sent',
      memberId: c.auth.memberId,
      data: { icon },
    });
    sendJson(c.res, 201, { gift });
  });

  // My pending (unopened) gift — null when there is none.
  route('GET', '/api/icongift', { auth: true }, (c) => {
    sendJson(c.res, 200, { gift: iconGiftsOf(c.auth.couple)[c.auth.memberId] ?? null });
  });

  // Unwrap: marks the gift opened (client then switches the app icon) and
  // tells the sender their surprise landed.
  route('POST', '/api/icongift/open', { auth: true }, (c) => {
    const gifts = iconGiftsOf(c.auth.couple);
    const gift = gifts[c.auth.memberId];
    if (!gift) throw httpError(404, 'no_gift', 'No pending icon gift');
    gift.openedAt = nowIso();
    delete gifts[c.auth.memberId];
    c.store.markDirty();
    c.realtime.sendToMember(c.auth.coupleId, gift.fromMemberId, 'icon_gift_opened', { gift });
    sendJson(c.res, 200, { gift });
  });

  // --- haptic duet ---------------------------------------------------------

  // Starts a synchronized haptic pattern on BOTH phones: the broadcast carries
  // a server-time `startAt` (now + lead-in); each client converts it to local
  // time via its WS clock offset (ping→pong `ts`), so the pattern hits both
  // wrists in the same instant.
  route('POST', '/api/duet', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    if (!Array.isArray(body.events) || body.events.length === 0 || body.events.length > DUET_MAX_EVENTS) {
      throw httpError(400, 'invalid_request', `"events" must be an array of 1..${DUET_MAX_EVENTS} haptic events`);
    }
    const events = body.events.map((ev, idx) => {
      const num = (v, name, min, max) => {
        if (typeof v !== 'number' || !Number.isFinite(v) || v < min || v > max) {
          throw httpError(400, 'invalid_request', `events[${idx}].${name} must be a number in ${min}..${max}`);
        }
        return v;
      };
      return {
        t: num(ev.t ?? 0, 't', 0, 30),
        i: num(ev.i ?? 0.5, 'i', 0, 1),
        s: num(ev.s ?? 0.5, 's', 0, 1),
        d: num(ev.d ?? 0, 'd', 0, 10),
      };
    });
    const name = body.name != null ? asString(body.name, 'name', { max: 80 }) : null;
    const duet = {
      id: id('duet'),
      name,
      events,
      startedBy: c.auth.memberId,
      startAtMs: Date.now() + DUET_LEAD_IN_MS,
      serverNowMs: Date.now(),
    };
    c.auth.couple.duetsPlayed = (c.auth.couple.duetsPlayed ?? 0) + 1; // badge: duet_partners
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'duet_start', { duet });
    sendJson(c.res, 201, { duet });
  });

  // --- date night ----------------------------------------------------------

  // Plans (or replaces) tonight's date: both phones start the Live Activity.
  route('POST', '/api/datenight', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const startsAtMs = Date.parse(asString(body.startsAt, 'startsAt', { max: 40 }));
    if (!Number.isFinite(startsAtMs)) {
      throw httpError(400, 'invalid_request', '"startsAt" must be an ISO-8601 date');
    }
    if (startsAtMs > Date.now() + DATE_NIGHT_MAX_FUTURE_MS) {
      throw httpError(400, 'invalid_request', '"startsAt" must be within the next 30 days');
    }
    const title = body.title != null ? asString(body.title, 'title', { max: 80 }) : null;
    const emoji = body.emoji != null ? asString(body.emoji, 'emoji', { max: 16 }) : null;
    const dateNight = {
      id: id('dn'),
      title,
      emoji,
      startsAt: new Date(startsAtMs).toISOString(),
      phase: startsAtMs > Date.now() ? 'anticipation' : 'live',
      createdBy: c.auth.memberId,
      createdAt: nowIso(),
      phaseChangedAt: nowIso(),
    };
    c.auth.couple.dateNight = dateNight;
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'datenight_update', { dateNight });
    emitAppEvent({
      store: c.store,
      realtime: c.realtime,
      couple: c.auth.couple,
      type: 'datenight_planned',
      memberId: c.auth.memberId,
      data: { dateNightId: dateNight.id },
    });
    sendJson(c.res, 201, { dateNight });
  });

  route('GET', '/api/datenight', { auth: true }, (c) => {
    sendJson(c.res, 200, { dateNight: c.auth.couple.dateNight ?? null });
  });

  // Phase switch (Vorfreude → Los → Ausklang) — also hit by the Live Activity
  // intent button; either partner may advance.
  route('POST', '/api/datenight/phase', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const dateNight = c.auth.couple.dateNight;
    if (!dateNight) throw httpError(404, 'no_datenight', 'No date night planned');
    dateNight.phase = asEnum(body.phase, 'phase', DATE_NIGHT_PHASES);
    dateNight.phaseChangedAt = nowIso();
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'datenight_update', { dateNight });
    sendJson(c.res, 200, { dateNight });
  });

  route('DELETE', '/api/datenight', { auth: true }, (c) => {
    if (!c.auth.couple.dateNight) throw httpError(404, 'no_datenight', 'No date night planned');
    c.auth.couple.dateNight = null;
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'datenight_update', { dateNight: null });
    sendJson(c.res, 200, { ok: true });
  });
}
