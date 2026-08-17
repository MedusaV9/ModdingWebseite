import { httpError, id, nowIso, readJsonObject, sendJson } from './util.js';

export const REPAIR_STEPS = Object.freeze([
  'creator_feeling',
  'partner_mirror',
  'partner_feeling',
  'creator_mirror',
  'creator_agreement',
  'partner_agreement',
]);

const LIMITS = Object.freeze({
  sessions: 60,
  text: 1_000,
  encryptedHints: 100,
  ciphertext: 8_192,
});

function sessionsOf(couple) {
  if (!couple.repairSessions) couple.repairSessions = [];
  return couple.repairSessions;
}

function hintsOf(couple) {
  if (!couple.considerationHints) couple.considerationHints = [];
  return couple.considerationHints;
}

function cap(list, limit) {
  if (list.length > limit) list.splice(0, list.length - limit);
}

function partnerOf(couple, memberId) {
  return couple.members.find((member) => member.id !== memberId) ?? null;
}

function expectedTurn(session) {
  const partnerId = session.memberIds.find((memberId) => memberId !== session.createdBy);
  const roles = [
    [session.createdBy, 'feeling'],
    [partnerId, 'mirror'],
    [partnerId, 'feeling'],
    [session.createdBy, 'mirror'],
    [session.createdBy, 'agreement'],
    [partnerId, 'agreement'],
  ];
  const [memberId, kind] = roles[session.step] ?? [null, null];
  return { memberId, kind };
}

function sessionView(session) {
  return {
    ...session,
    expected: session.status === 'active' ? expectedTurn(session) : null,
  };
}

function requireSession(couple, sessionId) {
  const session = sessionsOf(couple).find((candidate) => candidate.id === sessionId);
  if (!session) throw httpError(404, 'not_found', 'Unknown repair conversation');
  return session;
}

function activeHints(couple) {
  const now = Date.now();
  return hintsOf(couple)
    .filter((hint) => hint.pausedAt == null && Date.parse(hint.expiresAt) > now)
    .slice()
    .reverse();
}

export function registerRepairRoutes(route, { asString, asEnum }) {
  route('GET', '/api/repair', { auth: true }, (c) => {
    sendJson(c.res, 200, {
      sessions: sessionsOf(c.auth.couple).slice().reverse().map(sessionView),
    });
  });

  route('POST', '/api/repair', { auth: true }, async (c) => {
    const partner = partnerOf(c.auth.couple, c.auth.memberId);
    if (!partner) throw httpError(409, 'no_partner', 'Repair conversations need both partners');
    const body = await readJsonObject(c.req);
    const promptId = asString(body.promptId ?? 'listen', 'promptId', { max: 80 });
    const session = {
      id: id(),
      promptId,
      createdBy: c.auth.memberId,
      memberIds: [c.auth.memberId, partner.id],
      status: 'active',
      step: 0,
      entries: [],
      cooldownUntil: null,
      createdAt: nowIso(),
      completedAt: null,
    };
    const sessions = sessionsOf(c.auth.couple);
    sessions.push(session);
    cap(sessions, LIMITS.sessions);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'repair_changed', { session: sessionView(session) });
    sendJson(c.res, 201, { session: sessionView(session) });
  });

  route('GET', '/api/repair/:id', { auth: true }, (c) => {
    sendJson(c.res, 200, { session: sessionView(requireSession(c.auth.couple, c.params.id)) });
  });

  route('POST', '/api/repair/:id/turn', { auth: true }, async (c) => {
    const session = requireSession(c.auth.couple, c.params.id);
    if (session.status === 'completed') {
      throw httpError(409, 'already_completed', 'Repair conversation is already complete');
    }
    if (session.cooldownUntil && Date.parse(session.cooldownUntil) > Date.now()) {
      throw httpError(409, 'cooldown_active', 'The shared cooldown is still active');
    }
    session.cooldownUntil = null;
    const expected = expectedTurn(session);
    if (expected.memberId !== c.auth.memberId) {
      throw httpError(409, 'wrong_turn', 'Wait for your partner’s uninterrupted turn');
    }
    const body = await readJsonObject(c.req);
    const kind = asEnum(body.kind, 'kind', ['feeling', 'mirror', 'agreement']);
    if (kind !== expected.kind) {
      throw httpError(409, 'wrong_step', `Expected a ${expected.kind} response`);
    }
    const text = asString(body.text, 'text', { max: LIMITS.text });
    session.entries.push({
      id: id(),
      memberId: c.auth.memberId,
      kind,
      text,
      createdAt: nowIso(),
    });
    session.step += 1;
    if (session.step >= REPAIR_STEPS.length) {
      session.status = 'completed';
      session.completedAt = nowIso();
    }
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'repair_changed', { session: sessionView(session) });
    sendJson(c.res, 200, { session: sessionView(session) });
  });

  route('POST', '/api/repair/:id/cooldown', { auth: true }, async (c) => {
    const session = requireSession(c.auth.couple, c.params.id);
    if (session.status === 'completed') throw httpError(409, 'already_completed', 'Conversation is complete');
    const body = await readJsonObject(c.req);
    const minutes = Number(body.minutes);
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 60) {
      throw httpError(400, 'bad_minutes', '"minutes" must be an integer between 1 and 60');
    }
    session.cooldownUntil = new Date(Date.now() + minutes * 60_000).toISOString();
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'repair_changed', { session: sessionView(session) });
    sendJson(c.res, 200, { session: sessionView(session) });
  });

  // Consideration Radar stores opaque Vault-key ciphertext only. The sharing
  // level is visible metadata; the hint itself never reaches this server.
  route('GET', '/api/consideration', { auth: true }, (c) => {
    sendJson(c.res, 200, { hints: activeHints(c.auth.couple) });
  });

  route('POST', '/api/consideration', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    if (['text', 'note', 'label', 'title'].some((key) => body[key] != null)) {
      throw httpError(400, 'plaintext_forbidden', 'Consideration hints must be encrypted on device');
    }
    const ciphertext = asString(body.ciphertext, 'ciphertext', { max: LIMITS.ciphertext });
    if (!/^[A-Za-z0-9+/=]+$/.test(ciphertext) || ciphertext.length < 24) {
      throw httpError(400, 'bad_ciphertext', 'ciphertext must be a non-empty base64 envelope');
    }
    const visibility = asEnum(body.visibility ?? 'gentle', 'visibility', ['gentle', 'detail']);
    const hours = body.hours == null ? 24 : Number(body.hours);
    if (!Number.isInteger(hours) || hours < 1 || hours > 72) {
      throw httpError(400, 'bad_hours', '"hours" must be an integer between 1 and 72');
    }
    const hint = {
      id: id(),
      senderId: c.auth.memberId,
      ciphertext,
      visibility,
      createdAt: nowIso(),
      expiresAt: new Date(Date.now() + hours * 60 * 60_000).toISOString(),
      pausedAt: null,
    };
    const hints = hintsOf(c.auth.couple);
    hints.push(hint);
    cap(hints, LIMITS.encryptedHints);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'consideration_changed', { hint });
    sendJson(c.res, 201, { hint });
  });

  route('DELETE', '/api/consideration/:id', { auth: true }, (c) => {
    const hint = hintsOf(c.auth.couple).find((candidate) => candidate.id === c.params.id);
    if (!hint) throw httpError(404, 'not_found', 'Unknown consideration hint');
    if (hint.senderId !== c.auth.memberId) {
      throw httpError(403, 'not_yours', 'Only the sender can pause this hint');
    }
    if (!hint.pausedAt) hint.pausedAt = nowIso();
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'consideration_changed', { hint });
    sendJson(c.res, 200, { hint });
  });
}
