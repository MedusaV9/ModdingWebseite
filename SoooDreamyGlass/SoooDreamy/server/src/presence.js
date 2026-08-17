import { httpError, id, nowIso, readJsonObject, sendJson } from './util.js';

/**
 * „Nähe trotz Distanz" (v9.0) — presence modes + thinking-of-you pulses.
 *
 * Presence mode: a member can declare 🎯 focus or 😴 sleep (with an optional
 * note and auto-expiry). The partner's app shows a gentle hint instead of
 * expecting an answer. "available" is simply the absence of a mode.
 *
 * Pulses: a tiny "I'm thinking of you" with a fixed haptic pattern the
 * partner FEELS (live via WS when the app is open; queued otherwise and
 * replayed on the next launch — an unsigned build cannot buzz a killed app,
 * see docs/API.md honesty notes).
 *
 * Endpoints (registered from router.js):
 *   PUT    /api/presence      {mode:"focus"|"sleep", note?, minutes?}
 *   DELETE /api/presence      back to "available"
 *   POST   /api/pulses        {kind} → relayed/queued to the partner
 *   GET    /api/pulses        my unfelt pulses (oldest first)
 *   POST   /api/pulses/seen   mark all my unfelt pulses as felt
 *
 * No app events / XP on purpose: presence and pulses must stay a soft
 * signal, not a grind.
 */

export const PRESENCE_MODES = ['focus', 'sleep'];
export const PULSE_KINDS = ['thinking', 'goodnight', 'heartbeat', 'hug'];

export const PRESENCE_LIMITS = {
  note: 80,
  minMinutes: 5,
  maxMinutes: 720,       // 12 h — same ceiling as the energy light
  pulsesKept: 100,       // capped queue per couple
  pulseCooldownMs: 30_000, // one pulse per sender per 30 s — keeps it precious
};

/** Localized push bodies per pulse kind (the phone can't render the pattern in a banner). */
const PULSE_PUSH_BODY = {
  thinking: { de: 'Denkt gerade an dich. 💭', en: 'Is thinking of you right now. 💭' },
  goodnight: { de: 'Schickt dir ein Gute-Nacht-Signal. 🌙', en: 'Sends you a goodnight signal. 🌙' },
  heartbeat: { de: 'Schickt dir einen Herzschlag. 💓', en: 'Sends you a heartbeat. 💓' },
  hug: { de: 'Schickt dir eine Umarmung. 🤗', en: 'Sends you a hug. 🤗' },
};

// ---------------------------------------------------------------------------
// presence helpers

/**
 * A member's presence mode; `null` once the optional `until` passed (lazy
 * expiry — no timers, deterministic on both phones and after restarts).
 */
export function freshPresence(member) {
  const presence = member.presence;
  if (!presence) return null;
  if (presence.until != null && Date.parse(presence.until) <= Date.now()) return null;
  return presence;
}

function pulsesOf(couple) {
  if (!couple.pulses) couple.pulses = [];
  return couple.pulses;
}

function serializePulse(pulse) {
  return {
    id: pulse.id,
    kind: pulse.kind,
    senderId: pulse.senderId,
    createdAt: pulse.createdAt,
    feltAt: pulse.feltAt ?? null,
  };
}

// ---------------------------------------------------------------------------
// routes

export function registerPresenceRoutes(route, h) {
  // --- presence mode ---------------------------------------------------------

  route('PUT', '/api/presence', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const mode = h.asEnum(body.mode, 'mode', PRESENCE_MODES);
    const note = body.note == null
      ? null
      : h.asString(body.note, 'note', { max: PRESENCE_LIMITS.note, nonEmpty: false });
    let until = null;
    if (body.minutes != null) {
      const minutes = Number(body.minutes);
      if (!Number.isInteger(minutes) || minutes < PRESENCE_LIMITS.minMinutes
          || minutes > PRESENCE_LIMITS.maxMinutes) {
        throw httpError(400, 'bad_minutes',
          `"minutes" must be an integer between ${PRESENCE_LIMITS.minMinutes} and ${PRESENCE_LIMITS.maxMinutes}`);
      }
      until = new Date(Date.now() + minutes * 60_000).toISOString();
    }
    const presence = { mode, note, until, setAt: nowIso() };
    c.auth.member.presence = presence;
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'presence_mode',
      { memberId: c.auth.memberId, presence });
    sendJson(c.res, 200, { presence });
  });

  route('DELETE', '/api/presence', { auth: true }, (c) => {
    c.auth.member.presence = null;
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'presence_mode',
      { memberId: c.auth.memberId, presence: null });
    sendJson(c.res, 200, { ok: true });
  });

  // --- thinking-of-you pulses -------------------------------------------------

  route('POST', '/api/pulses', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const kind = h.asEnum(body.kind, 'kind', PULSE_KINDS);
    // Sync contract a: the clientOperationId dedup runs BEFORE the cooldown
    // check — a lost-response retry of an ACCEPTED pulse must return the
    // original pulse instead of a misleading 429 too_soon.
    const opKey = h.operationKey(c, 'pulse', '-', h.clientOperationId(body));
    if (h.hasClientOperation(c.auth.couple, opKey)) {
      sendJson(c.res, 200, { pulse: h.getClientOperation(c.auth.couple, opKey), duplicate: true });
      return;
    }
    const pulses = pulsesOf(c.auth.couple);
    // Cooldown counts LIVE sends only: a delivered Zeitpost pulse (viaPost,
    // post.js sweep) lands in this queue with createdAt = delivery time and
    // the SENDER's id — it must not (re)start the sender's cooldown, or a
    // server-side delivery turns a legitimate live pulse into a surprise
    // 429 too_soon with a countdown the user never started (arena finding).
    const last = [...pulses].reverse().find(
      (p) => p.senderId === c.auth.memberId && p.viaPost !== true,
    );
    if (last && Date.now() - Date.parse(last.createdAt) < PRESENCE_LIMITS.pulseCooldownMs) {
      const err = httpError(429, 'too_soon', 'One pulse per 30 seconds — make it count');
      // retry-after lets clients run a countdown ring instead of erroring.
      err.retryAfter = Math.max(
        1,
        Math.ceil((Date.parse(last.createdAt) + PRESENCE_LIMITS.pulseCooldownMs - Date.now()) / 1000),
      );
      throw err;
    }
    const pulse = { id: id('pl'), kind, senderId: c.auth.memberId, createdAt: nowIso(), feltAt: null };
    pulses.push(pulse);
    if (pulses.length > PRESENCE_LIMITS.pulsesKept) {
      pulses.splice(0, pulses.length - PRESENCE_LIMITS.pulsesKept);
    }
    h.rememberClientOperation(c.auth.couple, opKey, serializePulse(pulse));
    c.store.markDirty();
    c.realtime.broadcastPartner(c.auth.coupleId, c.auth.memberId, 'pulse',
      { pulse: serializePulse(pulse) });
    h.notifyPartner(c, {
      type: 'pulse',
      title: { de: c.auth.member.name, en: c.auth.member.name },
      body: PULSE_PUSH_BODY[kind],
      link: 'sooodreamy://tab/home',
    });
    sendJson(c.res, 201, { pulse: serializePulse(pulse) });
  });

  route('GET', '/api/pulses', { auth: true }, (c) => {
    const pulses = pulsesOf(c.auth.couple)
      .filter((p) => p.senderId !== c.auth.memberId && p.feltAt == null)
      .map(serializePulse);
    sendJson(c.res, 200, { pulses });
  });

  route('POST', '/api/pulses/seen', { auth: true }, (c) => {
    const felt = [];
    for (const pulse of pulsesOf(c.auth.couple)) {
      if (pulse.senderId !== c.auth.memberId && pulse.feltAt == null) {
        pulse.feltAt = nowIso();
        felt.push(pulse.id);
      }
    }
    if (felt.length > 0) {
      c.store.markDirty();
      // The sender learns their pulses actually reached a heart.
      c.realtime.broadcastPartner(c.auth.coupleId, c.auth.memberId, 'pulse_felt',
        { memberId: c.auth.memberId, ids: felt });
    }
    sendJson(c.res, 200, { ok: true, count: felt.length });
  });
}
