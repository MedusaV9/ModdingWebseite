import { httpError, id, nowIso, readJsonObject, sendJson } from './util.js';
import { PULSE_KINDS, PRESENCE_LIMITS } from './presence.js';

/**
 * „Post-Station" (FullRelease P6-B) — sending becomes a little post office:
 * scheduled deliveries ("Zeitpost"), echo replies and a shared journal.
 *
 * Zeitpost: a touch, a pulse or a short note (≤120 chars) scheduled 5 min to
 * 7 days ahead (server clock, max 5 open per person). Delivery happens via
 * the store-wide sweep below (same setInterval pattern as the week-review
 * arrival push) and produces the NORMAL touch/pulse/note event + push + WS
 * fanout — the receiver never learns something is pending (surprise!).
 * Delivery guarantee (FullRelease R1-C): exactly-once for the ARTIFACT
 * (stable post-derived artifact id + durable transition before any side
 * effect), at-least-once for the notification — see postDeliverySweep.
 *
 * Echoes: a received touch can be sent back ONCE within 10 minutes — same
 * kind, marked `echo: true` + `echoOf`, no cooldown. Echoing an ECHO is
 * refused (409 echo_taken): the client never offered a counter-echo anywhere
 * (overlay or journal), so ping-pong chains were never reachable in practice
 * — FullRelease R1-C makes the server say the same truth.
 *
 * Journal: the last 30 days of touches/pulses/delivered notes of BOTH
 * partners as one chronology ("Posteingang der Zärtlichkeiten").
 *
 * Endpoints (registered from router.js):
 *   POST   /api/post/schedule        {kind, type?|pulseKind?|note?, deliverAt}
 *   GET    /api/post/scheduled       my OWN open posts (partner never sees them)
 *   DELETE /api/post/scheduled/:id   cancel one of my own posts
 *   POST   /api/touches/:id/echo     send a received touch back (once, ≤10 min)
 *   GET    /api/post/journal?limit=  merged 30-day chronology of both partners
 *
 * Error codes: post_limit (409), echo_expired (409), echo_taken (409),
 * bad_deliver_at (400).
 */

export const POST_KINDS = ['touch', 'pulse', 'note'];

export const POST_LIMITS = {
  note: 120,             // note length ("kurze Notiz")
  maxOpen: 5,            // open scheduled posts per member
  minLeadMs: 5 * 60_000, // deliverAt must be ≥ 5 min ahead …
  leadGraceMs: 30_000,   // … minus a little clock-skew grace
  maxLeadMs: 7 * 24 * 60 * 60_000, // … and ≤ 7 days ahead
  echoWindowMs: 10 * 60_000, // a touch can be echoed for 10 minutes
  echoesKeptMs: 24 * 60 * 60_000, // echo markers pruned after a day
  notesKept: 200,        // delivered notes kept per couple
  journalDays: 30,
  journalDefaultLimit: 100,
  journalMaxLimit: 300,
  touchesKept: 500,      // mirrors router.js LIMITS.touches (single cap, two writers)
};

// Arena/Test only: POST_MIN_LEAD_SECONDS (env) shrinks the 5-minute minimum
// scheduling lead so live end-to-end harnesses (tools/arena) can exercise
// REAL Zeitpost deliveries within seconds instead of minutes. Applied ONLY
// when the variable is set to a non-negative number of seconds — when unset,
// POST_LIMITS stays byte-identical to the shipped defaults above.
if (process.env.POST_MIN_LEAD_SECONDS !== undefined) {
  const overrideSeconds = Number(process.env.POST_MIN_LEAD_SECONDS);
  if (Number.isFinite(overrideSeconds) && overrideSeconds >= 0) {
    POST_LIMITS.minLeadMs = overrideSeconds * 1000;
  }
}

// ---------------------------------------------------------------------------
// store accessor + small local helpers

/** `{ scheduled: [...], notes: [...], echoes: { [touchId]: {by, touchId, at} } }` */
function postOf(couple) {
  if (!couple.post) couple.post = {};
  if (!Array.isArray(couple.post.scheduled)) couple.post.scheduled = [];
  if (!Array.isArray(couple.post.notes)) couple.post.notes = [];
  if (!couple.post.echoes || typeof couple.post.echoes !== 'object') couple.post.echoes = {};
  return couple.post;
}

function capListLocal(list, max) {
  if (list.length > max) list.splice(0, list.length - max);
}

/** Mirrors router.js touchCounter — one counter, two writers (touch route + delivery). */
function bumpTouchCounter(couple, memberId, type) {
  if (!couple.counters) couple.counters = {};
  if (!couple.counters.touches) couple.counters.touches = {};
  const counters = couple.counters.touches;
  if (!counters[memberId]) counters[memberId] = { total: 0, byType: {} };
  counters[memberId].total += 1;
  counters[memberId].byType[type] = (counters[memberId].byType[type] ?? 0) + 1;
}

/** Echo markers outlive the capped touch list but not forever — prune after a day. */
function pruneEchoes(box, now = Date.now()) {
  const horizon = new Date(now - POST_LIMITS.echoesKeptMs).toISOString();
  for (const [touchId, marker] of Object.entries(box.echoes)) {
    if ((marker?.at ?? '') < horizon) delete box.echoes[touchId];
  }
}

function serializeScheduledPost(post) {
  return {
    id: post.id,
    kind: post.kind,
    type: post.touchType ?? null,
    pulseKind: post.pulseKind ?? null,
    note: post.note ?? null,
    deliverAt: post.deliverAt,
    senderId: post.senderId,
    createdAt: post.createdAt,
  };
}

// Strict RFC-3339/ISO-8601 timestamp WITH timezone (regex + Date.parse combo,
// same pattern as util.js isValidDateKey). Date.parse alone also swallows
// RFC-1123 dates ("Tue, 18 Aug 2026 …") and zone-less local times — both must
// be a 400, not a silent server-local guess (FullRelease R1-C).
const DELIVER_AT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

function asDeliverAt(value) {
  const at = typeof value === 'string' && DELIVER_AT_RE.test(value)
    ? Date.parse(value)
    : Number.NaN;
  if (Number.isNaN(at)) {
    throw httpError(400, 'bad_deliver_at',
      '"deliverAt" must be an RFC-3339/ISO-8601 timestamp with timezone (e.g. 2026-08-18T14:00:00Z)');
  }
  const lead = at - Date.now();
  if (lead < POST_LIMITS.minLeadMs - POST_LIMITS.leadGraceMs) {
    throw httpError(400, 'bad_deliver_at', '"deliverAt" must be at least 5 minutes ahead');
  }
  if (lead > POST_LIMITS.maxLeadMs) {
    throw httpError(400, 'bad_deliver_at', '"deliverAt" must be at most 7 days ahead');
  }
  return new Date(at).toISOString();
}

// ---------------------------------------------------------------------------
// delivery — the sweep runs OUTSIDE a request (no session, no origin marker)

const DELIVERY_PUSH = {
  touch: {
    de: 'Eine Zeitpost von deinem Schatz ist angekommen. 💌',
    en: 'A timed delivery from your sweetheart just arrived. 💌',
  },
  pulse: {
    de: 'Eine Zeitpost pulsiert für dich. 💗',
    en: 'A timed delivery is pulsing for you. 💗',
  },
  note: {
    // Lock-screen privacy: the note text stays inside the app on purpose.
    de: 'Eine kleine Notiz ist für dich angekommen. 💌',
    en: 'A little note has arrived for you. 💌',
  },
};

/**
 * Stable artifact id, derived from the post id (FullRelease R1-C): one
 * scheduled post can only ever mint ONE artifact, no matter how often the
 * sweep re-attempts it. Keeps the normal prefix convention (t_/pl_/pn_) and
 * can never collide with a random id('t') (those are exactly prefix+16 hex).
 */
function artifactIdFor(post) {
  const prefix = post.kind === 'touch' ? 't' : post.kind === 'pulse' ? 'pl' : 'pn';
  return `${prefix}_${post.id}`;
}

/**
 * Phase 1 of a delivery — the durable outbox transition (FullRelease R1-C):
 * removes the post from the open list AND creates the target artifact under
 * its stable id in ONE synchronous step (no awaits, no side effects), so any
 * journal snapshot sees both or neither. Idempotent by construction: when the
 * artifact already exists (crash-recovery re-sweep, regressed .bak
 * generation), nothing is created and no counter is bumped — the caller only
 * redoes the fanout. Returns the artifact to fan out.
 */
function applyDeliveryTransition(couple, post) {
  const scheduled = couple.post?.scheduled ?? [];
  const idx = scheduled.indexOf(post);
  if (idx !== -1) scheduled.splice(idx, 1);
  const artifactId = artifactIdFor(post);
  const deliveredAt = nowIso();
  if (post.kind === 'touch') {
    const existing = couple.touches.find((t) => t.id === artifactId);
    if (existing) return existing;
    const touch = {
      id: artifactId, type: post.touchType, senderId: post.senderId,
      createdAt: deliveredAt, viaPost: true, postId: post.id,
    };
    couple.touches.push(touch);
    capListLocal(couple.touches, POST_LIMITS.touchesKept);
    bumpTouchCounter(couple, post.senderId, post.touchType);
    return touch;
  }
  if (post.kind === 'pulse') {
    if (!couple.pulses) couple.pulses = [];
    const existing = couple.pulses.find((p) => p.id === artifactId);
    if (existing) return existing;
    const pulse = {
      id: artifactId, kind: post.pulseKind, senderId: post.senderId,
      createdAt: deliveredAt, feltAt: null, viaPost: true, postId: post.id,
    };
    couple.pulses.push(pulse);
    capListLocal(couple.pulses, PRESENCE_LIMITS.pulsesKept);
    return pulse;
  }
  const box = postOf(couple);
  const existing = box.notes.find((n) => n.id === artifactId);
  if (existing) return existing;
  const note = {
    id: artifactId, text: post.note, senderId: post.senderId,
    createdAt: deliveredAt, postId: post.id,
  };
  box.notes.push(note);
  capListLocal(box.notes, POST_LIMITS.notesKept);
  return note;
}

/** Phase 2 of a delivery — WS fanout + push, AFTER the transition persisted. */
function fanOutDelivery({ store, realtime, push, couple, post, artifact, log }) {
  const sender = couple.members.find((m) => m.id === post.senderId);
  const senderName = sender?.name ?? '?';
  if (post.kind === 'touch') {
    // broadcastCouple = partner devices + ALL sender devices: there is no
    // calling session to exclude, every device converges via the same frame.
    realtime.broadcastCouple(couple.id, 'touch', { touch: artifact });
  } else if (post.kind === 'pulse') {
    realtime.broadcastCouple(couple.id, 'pulse', {
      pulse: {
        id: artifact.id, kind: artifact.kind, senderId: artifact.senderId,
        createdAt: artifact.createdAt, feltAt: null, viaPost: true,
      },
    });
  } else {
    realtime.broadcastCouple(couple.id, 'post_note', { note: artifact });
  }
  void push.notifyPartner({
    store,
    couple,
    senderMemberId: post.senderId,
    type: post.kind === 'note' ? 'post' : post.kind,
    title: { de: `Von ${senderName}`, en: `From ${senderName}` },
    body: DELIVERY_PUSH[post.kind],
    link: 'sooodreamy://tab/home',
  }).catch((error) => log('post: delivery push failed', error?.message ?? error));
}

/**
 * One sweep over all couples; delivers every due scheduled post. Delivery is
 * a durable outbox transition (FullRelease R1-C), per post:
 *
 *   1. remove the post from the open list + create the artifact under its
 *      STABLE post-derived id (one synchronous state transition),
 *   2. store.markDirty() — a synchronous fsynced write-ahead-journal commit
 *      (store.js), so the transition is durable BEFORE any side effect,
 *   3. only then WS fanout + push.
 *
 * Crash before 2: neither artifact nor delivery persisted — the post is still
 * open after restart and the sweep re-attempts it (at-least-once for the
 * notification). The stable artifact id makes the re-attempt idempotent:
 * an already-existing artifact is never duplicated, only its fanout is
 * redone — exactly-once for the artifact. Crash after 2 before 3: the
 * artifact exists, that one push/WS fanout is lost (accepted and documented
 * in API.md — devices converge via their normal fetches).
 *
 * `testCrashPoint(phase, post)` is a test-only hook ('before-persist' /
 * 'after-persist') so the crash windows can be hit deterministically
 * (post_crash.test.js kills the process inside it). Returns the number
 * delivered.
 */
export function postDeliverySweep({
  store, realtime, push, log = () => {}, now = new Date(), testCrashPoint = null,
}) {
  const nowMs = now.getTime();
  let delivered = 0;
  for (const couple of Object.values(store.data.couples ?? {})) {
    const scheduled = couple.post?.scheduled;
    if (!scheduled?.length) continue;
    const due = scheduled
      .filter((p) => Date.parse(p.deliverAt) <= nowMs)
      .sort((a, b) => (a.deliverAt < b.deliverAt ? -1 : a.deliverAt > b.deliverAt ? 1 : 0));
    if (due.length === 0) continue;
    for (const post of due) {
      try {
        const artifact = applyDeliveryTransition(couple, post);
        testCrashPoint?.('before-persist', post);
        store.markDirty();
        testCrashPoint?.('after-persist', post);
        fanOutDelivery({ store, realtime, push, couple, post, artifact, log });
        delivered += 1;
      } catch (err) {
        log('post: delivery failed', err?.message ?? err);
      }
    }
  }
  return delivered;
}

/** Interval wrapper (30 s default — min lead is 5 min, so ±30 s is invisible). 0 disables. */
export function startPostDeliveryScheduler({
  store, realtime, push, log = () => {}, intervalSeconds = 30,
}) {
  if (!Number.isFinite(intervalSeconds) || intervalSeconds <= 0) return () => {};
  const timer = setInterval(() => {
    try {
      postDeliverySweep({ store, realtime, push, log });
    } catch (err) {
      log('post: delivery sweep failed', err);
    }
  }, intervalSeconds * 1000);
  timer.unref?.();
  return () => clearInterval(timer);
}

// ---------------------------------------------------------------------------
// journal — one merged 30-day chronology of both partners

/**
 * Newest first; same-instant entries break the tie on id (deterministic —
 * PostRules.swift mirrors this order bit-for-bit). Undelivered scheduled
 * posts are NEVER part of the journal: the surprise stays a surprise.
 */
export function buildJournal(couple, { limit = POST_LIMITS.journalDefaultLimit, now = Date.now() } = {}) {
  const horizon = new Date(now - POST_LIMITS.journalDays * 86_400_000).toISOString();
  const entries = [];
  for (const t of couple.touches ?? []) {
    if (t.createdAt < horizon) continue;
    entries.push({
      id: t.id, kind: 'touch', type: t.type, pulseKind: null, note: null,
      senderId: t.senderId, createdAt: t.createdAt,
      echo: t.echo === true, echoOf: t.echoOf ?? null, viaPost: t.viaPost === true,
    });
  }
  for (const p of couple.pulses ?? []) {
    if (p.createdAt < horizon) continue;
    entries.push({
      id: p.id, kind: 'pulse', type: null, pulseKind: p.kind, note: null,
      senderId: p.senderId, createdAt: p.createdAt,
      echo: false, echoOf: null, viaPost: p.viaPost === true,
    });
  }
  for (const n of couple.post?.notes ?? []) {
    if (n.createdAt < horizon) continue;
    entries.push({
      id: n.id, kind: 'note', type: null, pulseKind: null, note: n.text,
      senderId: n.senderId, createdAt: n.createdAt,
      echo: false, echoOf: null, viaPost: true,
    });
  }
  entries.sort((x, y) => (
    x.createdAt < y.createdAt ? 1 : x.createdAt > y.createdAt ? -1
      : x.id < y.id ? 1 : x.id > y.id ? -1 : 0
  ));
  return entries.slice(0, limit);
}

// ---------------------------------------------------------------------------
// routes

export function registerPostRoutes(route, h) {
  // --- Zeitpost: schedule / list own / cancel --------------------------------

  route('POST', '/api/post/schedule', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const kind = h.asEnum(body.kind, 'kind', POST_KINDS);
    let touchType = null;
    let pulseKind = null;
    let note = null;
    if (kind === 'touch') touchType = h.asEnum(body.type, 'type', h.touchTypes);
    else if (kind === 'pulse') pulseKind = h.asEnum(body.pulseKind, 'pulseKind', PULSE_KINDS);
    else note = h.asString(body.note, 'note', { max: POST_LIMITS.note });
    // Sync contract a: the clientOperationId dedup runs BEFORE the deliverAt
    // check — a lost-response retry of an ACCEPTED schedule must return the
    // original post, even when its deliverAt has meanwhile slipped past the
    // 5-minute lead. Only a schedule the server never saw gets bad_deliver_at
    // on replay (the outbox turns that 400 into a giveUp poison pill).
    const opKey = h.operationKey(c, 'post-schedule', '-', h.clientOperationId(body));
    if (h.hasClientOperation(c.auth.couple, opKey)) {
      sendJson(c.res, 200, { post: h.getClientOperation(c.auth.couple, opKey), duplicate: true });
      return;
    }
    const deliverAt = asDeliverAt(body.deliverAt);
    const box = postOf(c.auth.couple);
    const mine = box.scheduled.filter((p) => p.senderId === c.auth.memberId);
    if (mine.length >= POST_LIMITS.maxOpen) {
      throw httpError(409, 'post_limit',
        `At most ${POST_LIMITS.maxOpen} open scheduled posts per person — deliver or cancel some first`);
    }
    const post = {
      id: id('zp'), kind, touchType, pulseKind, note,
      deliverAt, senderId: c.auth.memberId, createdAt: nowIso(),
    };
    box.scheduled.push(post);
    h.rememberClientOperation(c.auth.couple, opKey, serializeScheduledPost(post));
    c.store.markDirty();
    // Surprise contract: ONLY the sender's other devices learn about the
    // pending post — the partner gets nothing until delivery.
    c.realtime.sendToMember(c.auth.coupleId, c.auth.memberId, 'post_scheduled',
      { post: serializeScheduledPost(post) }, { exceptSessionId: c.auth.record.sessionId });
    sendJson(c.res, 201, { post: serializeScheduledPost(post) });
  });

  route('GET', '/api/post/scheduled', { auth: true }, (c) => {
    const posts = postOf(c.auth.couple).scheduled
      .filter((p) => p.senderId === c.auth.memberId)
      .map(serializeScheduledPost)
      .sort((a, b) => (a.deliverAt < b.deliverAt ? -1 : a.deliverAt > b.deliverAt ? 1 : 0));
    sendJson(c.res, 200, { posts });
  });

  route('DELETE', '/api/post/scheduled/:id', { auth: true }, (c) => {
    const box = postOf(c.auth.couple);
    // The partner's pending posts answer 404 like they don't exist — a probe
    // must not be able to tell "not mine" from "not there" (surprise!).
    const idx = box.scheduled.findIndex(
      (p) => p.id === c.params.id && p.senderId === c.auth.memberId);
    if (idx === -1) throw httpError(404, 'not_found', 'Unknown scheduled post');
    box.scheduled.splice(idx, 1);
    c.store.markDirty();
    c.realtime.sendToMember(c.auth.coupleId, c.auth.memberId, 'post_canceled',
      { id: c.params.id }, { exceptSessionId: c.auth.record.sessionId });
    sendJson(c.res, 200, { ok: true });
  });

  // --- echo replies -----------------------------------------------------------

  route('POST', '/api/touches/:id/echo', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const couple = c.auth.couple;
    // Dedup FIRST (sync contract a): a lost-response retry must return the
    // original echo even when the 10-minute window has meanwhile closed.
    const opKey = h.operationKey(c, 'echo', c.params.id, h.clientOperationId(body));
    if (h.hasClientOperation(couple, opKey)) {
      sendJson(c.res, 200, { touch: h.getClientOperation(couple, opKey), duplicate: true });
      return;
    }
    const original = couple.touches.find((t) => t.id === c.params.id);
    if (!original) throw httpError(404, 'not_found', 'Unknown touch');
    if (original.senderId === c.auth.memberId) {
      throw httpError(400, 'invalid_request', 'Only a received touch can be sent back');
    }
    // FullRelease R1-C: one bounce per touch, full stop. The client never
    // offered a counter-echo (overlay or journal), so echo chains were never
    // reachable in practice — the server now enforces that lived truth too.
    if (original.echo === true) {
      throw httpError(409, 'echo_taken',
        'An echo cannot be sent back again — one bounce per touch');
    }
    const box = postOf(couple);
    pruneEchoes(box);
    if (box.echoes[original.id] || couple.touches.some((t) => t.echoOf === original.id)) {
      throw httpError(409, 'echo_taken', 'This touch has already been sent back once');
    }
    if (Date.now() - Date.parse(original.createdAt) > POST_LIMITS.echoWindowMs) {
      throw httpError(409, 'echo_expired', 'A touch can be sent back within 10 minutes');
    }
    // No cooldown on purpose — an echo is one tap of gratitude, not spam
    // (the once-per-original rule bounds it harder than any cooldown).
    const touch = {
      id: id('t'), type: original.type, senderId: c.auth.memberId,
      createdAt: nowIso(), echo: true, echoOf: original.id,
    };
    couple.touches.push(touch);
    capListLocal(couple.touches, POST_LIMITS.touchesKept);
    bumpTouchCounter(couple, c.auth.memberId, touch.type);
    box.echoes[original.id] = { by: c.auth.memberId, touchId: touch.id, at: touch.createdAt };
    h.rememberClientOperation(couple, opKey, touch);
    c.store.markDirty();
    c.realtime.broadcastPartner(c.auth.coupleId, c.auth.memberId, 'touch', { touch });
    c.realtime.sendToMember(c.auth.coupleId, c.auth.memberId, 'touch', { touch }, {
      exceptSessionId: c.auth.record.sessionId,
    });
    h.notifyPartner(c, {
      type: 'touch',
      title: { de: `Von ${c.auth.member.name}`, en: `From ${c.auth.member.name}` },
      body: {
        de: 'Deine Berührung kam als Echo zurück. 💞',
        en: 'Your touch came back as an echo. 💞',
      },
      link: 'sooodreamy://tab/home',
    });
    sendJson(c.res, 201, { touch });
  });

  // --- journal ------------------------------------------------------------------

  route('GET', '/api/post/journal', { auth: true }, (c) => {
    const limit = h.queryInt(c.url, 'limit',
      POST_LIMITS.journalDefaultLimit, 1, POST_LIMITS.journalMaxLimit);
    sendJson(c.res, 200, { entries: buildJournal(c.auth.couple, { limit }) });
  });
}
