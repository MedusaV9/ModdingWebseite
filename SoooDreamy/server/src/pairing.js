import crypto from 'node:crypto';
import QRCode from 'qrcode';
import { httpError, nowIso, readJsonObject, sendJson, sha256Hex } from './util.js';
import {
  activeSessionCount,
  createSession,
  invalidateLinkCodes,
  issueLinkCode,
  MAX_SESSIONS_PER_MEMBER,
  requestKey,
  SESSION_REJOIN_GRACE_MS,
  sessionOrigin,
  tokenDigest,
  validateLinkCode,
} from './security.js';

// ---------------------------------------------------------------------------
// v6.1 pairing recovery: a full couple must never become permanently
// unjoinable. Three re-attach proofs exist, strongest first:
//
//   1. recovery key  — per-member secret issued at pairing time (and on
//      demand); survives app reinstalls when the client keeps it in the
//      iCloud keychain. Stored server-side only as a SHA-256 digest.
//   2. old bearer    — an expired (but never revoked) session token still
//      proves the device once belonged to this member slot.
//   3. replace code  — the remaining partner explicitly approves replacing
//      the other slot's device(s); short-lived and single-use.
//
// All three re-attach to the EXISTING member slot — history, stats and the
// couple itself stay untouched.

const REPLACE_CODE_TTL_MS = 15 * 60 * 1000;
const REPLACE_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const REPLACE_CODE_LENGTH = 8;

export function newRecoveryKey() {
  return `rec_${crypto.randomBytes(20).toString('hex')}`;
}

function newReplaceCode() {
  let code = '';
  for (let i = 0; i < REPLACE_CODE_LENGTH; i++) {
    code += REPLACE_CODE_ALPHABET[crypto.randomInt(REPLACE_CODE_ALPHABET.length)];
  }
  return code;
}

/** Constant-time comparison of two hex digests. */
function digestsEqual(a, b) {
  const left = Buffer.from(String(a ?? ''));
  const right = Buffer.from(String(b ?? ''));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

/**
 * Issues (or rotates) a member's recovery key. Only the digest is stored;
 * the plaintext is returned exactly once and never again.
 */
export function issueRecoveryKey(member) {
  const recoveryKey = newRecoveryKey();
  member.recovery = { digest: sha256Hex(recoveryKey), createdAt: nowIso() };
  return recoveryKey;
}

function findCoupleByCode(store, code) {
  const couple = Object.values(store.data.couples).find((cp) => cp.code === code);
  if (!couple) throw httpError(404, 'unknown_code', 'No couple with this code');
  return couple;
}

function memberByRecoveryKey(couple, recoveryKey) {
  const digest = sha256Hex(recoveryKey);
  const upperDigest = sha256Hex(recoveryKey.trim().toUpperCase());
  const lowerDigest = sha256Hex(recoveryKey.trim().toLowerCase());
  return couple.members.find((member) => {
    if (member.recovery?.digest) {
      if (digestsEqual(member.recovery.digest, digest)
        || digestsEqual(member.recovery.digest, upperDigest)
        || digestsEqual(member.recovery.digest, lowerDigest)) return true;
    }
    return false;
  }) ?? null;
}

function pendingReplace(couple) {
  const pending = couple.partnerReplace;
  if (!pending || pending.usedAt) return null;
  if (Date.parse(pending.expiresAt) <= Date.now()) return null;
  return pending;
}

/**
 * Sync contract d: session lifecycle frame to ALL devices of the affected
 * member (the partner is deliberately NOT notified — device management stays
 * a per-member concern). `reason` is one of `linked`/`rejoined`/`replaced`/
 * `rotated`/`revoked`.
 */
function notifySessionsChanged(realtime, coupleId, memberId, reason, record) {
  realtime.sendToMember(coupleId, memberId, 'sessions_changed', {
    memberId,
    reason,
    sessionId: record.sessionId,
    deviceName: record.deviceName ?? null,
  });
}

/** Revokes every session of one member and drops its push registrations. */
function revokeAllMemberSessions({ store, realtime, push, couple, memberId }) {
  const deviceIds = new Set();
  for (const record of Object.values(store.data.tokens)) {
    if (record.coupleId !== couple.id || record.memberId !== memberId) continue;
    if (!record.revokedAt) {
      record.revokedAt = nowIso();
      // Frame first (so still-open sockets hear it), then the 4001 close.
      notifySessionsChanged(realtime, couple.id, memberId, 'revoked', record);
    }
    deviceIds.add(record.deviceId);
    realtime.closeSession(record.sessionId, 'member slot replaced');
  }
  for (const deviceId of deviceIds) {
    push.unregisterDevice({ store, couple, memberId, deviceId });
  }
  // Cutting off a member's devices must also void any pending device link
  // code — otherwise the replaced slot's old holder could mint a fresh
  // session right through the replacement.
  invalidateLinkCodes(store, { coupleId: couple.id, memberId });
}

/** scheme://host of this request — the default server base URL for QR deep links. */
function requestBaseUrl(req, trustProxy) {
  const secure = req.socket.encrypted === true
    || (trustProxy === true && req.headers['x-forwarded-proto'] === 'https');
  return `${secure ? 'https' : 'http'}://${req.headers.host ?? 'localhost'}`;
}

export function registerPairingRoutes(route, {
  asString,
  serializeMember,
  serializeCouple,
  partnerOf,
}) {
  function sessionResponse(c, couple, member, body, extra = {}) {
    const { token, record } = createSession(c.store, {
      coupleId: couple.id,
      memberId: member.id,
      deviceId: body.deviceId,
      deviceName: body.deviceName,
    });
    c.store.markDirty();
    sendJson(c.res, 200, {
      token,
      sessionId: record.sessionId,
      expiresAt: record.expiresAt,
      coupleId: couple.id,
      memberId: member.id,
      couple: serializeCouple(couple, c.realtime),
      ...extra,
    });
    return { token, record };
  }

  // --- recovery keys --------------------------------------------------------

  route('GET', '/api/recovery-key', { auth: true }, (c) => {
    sendJson(c.res, 200, {
      configured: Boolean(c.auth.member.recovery),
      createdAt: c.auth.member.recovery?.createdAt ?? null,
    });
  });

  // Generates (or rotates) the caller's recovery key. Couples created before
  // v6.1 have none — the app calls this once after updating and stores the
  // plaintext in the keychain. Rotation invalidates the previous key.
  route('POST', '/api/recovery-key', { auth: true }, (c) => {
    const rotated = Boolean(c.auth.member.recovery);
    const recoveryKey = issueRecoveryKey(c.auth.member);
    c.store.markDirty();
    c.log(`pairing: recovery key ${rotated ? 'rotated' : 'issued'} for member ${c.auth.memberId}`);
    sendJson(c.res, 200, { recoveryKey, createdAt: c.auth.member.recovery.createdAt, rotated });
  });

  // --- re-attach (rejoin) ---------------------------------------------------

  // Re-attaches a device to its OWN member slot of an already-full couple.
  // Exactly one proof is required: {code + recoveryKey}, {token} (an old,
  // possibly expired bearer), or {code + replaceCode} (partner-approved).
  route('POST', '/api/couples/rejoin', { auth: false }, async (c) => {
    c.rateLimiter.consume('coupleRejoin', requestKey(c.req));
    const body = await readJsonObject(c.req);

    if (typeof body.recoveryKey === 'string') {
      const code = asString(body.code, 'code', { max: 12 }).trim().toUpperCase();
      const recoveryKey = asString(body.recoveryKey, 'recoveryKey', { max: 200 }).trim();
      const couple = findCoupleByCode(c.store, code);
      const member = memberByRecoveryKey(couple, recoveryKey);
      if (!member) {
        throw httpError(403, 'bad_recovery_key', 'Recovery key does not match any member of this couple');
      }
      c.log(`pairing: member ${member.id} rejoined couple ${couple.id} via recovery key`);
      c.realtime.broadcastPartner(couple.id, member.id, 'partner_rejoined', {
        member: serializeMember(couple, member, c.realtime),
      });
      const { record } = sessionResponse(c, couple, member, body, { rejoined: true, method: 'recoveryKey' });
      notifySessionsChanged(c.realtime, couple.id, member.id, 'rejoined', record);
      return;
    }

    if (typeof body.token === 'string') {
      const token = asString(body.token, 'token', { max: 400 }).trim();
      const digest = tokenDigest(token);
      const qrNonce = c.store.data.qrNonces?.[digest];
      if (qrNonce) {
        if (qrNonce.consumedAt) {
          throw httpError(409, 'qr_consumed', 'This admin login QR was already used');
        }
        if (Date.parse(qrNonce.expiresAt) <= Date.now()) {
          throw httpError(403, 'qr_expired', 'This admin login QR has expired — ask the server owner for a new one');
        }
        const couple = c.store.data.couples[qrNonce.coupleId];
        const member = couple?.members.find((candidate) => candidate.id === qrNonce.memberId);
        if (!member) {
          throw httpError(404, 'unknown_couple', 'The member slot of this admin login QR no longer exists');
        }
        qrNonce.consumedAt = nowIso();
        c.log(`pairing: member ${member.id} rejoined couple ${couple.id} via one-time admin QR`);
        c.realtime.broadcastPartner(couple.id, member.id, 'partner_rejoined', {
          member: serializeMember(couple, member, c.realtime),
        });
        const { record: qrSession } = sessionResponse(c, couple, member, body, { rejoined: true, method: 'adminQr' });
        notifySessionsChanged(c.realtime, couple.id, member.id, 'rejoined', qrSession);
        return;
      }

      const record = c.store.data.tokens[digest];
      if (!record) throw httpError(403, 'unknown_session', 'This token was never issued by this server');
      if (record.revokedAt) {
        throw httpError(403, 'session_revoked', 'This session was revoked — ask your partner for a replace code');
      }
      const expiresAt = Date.parse(record.expiresAt);
      if (!Number.isFinite(expiresAt) || expiresAt + SESSION_REJOIN_GRACE_MS <= Date.now()) {
        delete c.store.data.tokens[digest];
        c.store.markDirty();
        throw httpError(
          403,
          'session_expired',
          'This session expired beyond the 24-hour rejoin grace — use your recovery key or ask for a replace code',
        );
      }
      const couple = c.store.data.couples[record.coupleId];
      const member = couple?.members.find((m) => m.id === record.memberId);
      if (!member) throw httpError(404, 'unknown_couple', 'The couple of this session no longer exists');
      // The old record has served its purpose as proof; expired ones are
      // dropped so the token store does not accumulate dead sessions.
      if (Date.parse(record.expiresAt) <= Date.now()) delete c.store.data.tokens[digest];
      c.log(`pairing: member ${member.id} rejoined couple ${couple.id} via previous session token`);
      c.realtime.broadcastPartner(couple.id, member.id, 'partner_rejoined', {
        member: serializeMember(couple, member, c.realtime),
      });
      const { record: tokenSession } = sessionResponse(c, couple, member, body, { rejoined: true, method: 'token' });
      notifySessionsChanged(c.realtime, couple.id, member.id, 'rejoined', tokenSession);
      return;
    }

    if (typeof body.replaceCode === 'string') {
      const code = asString(body.code, 'code', { max: 12 }).trim().toUpperCase();
      const replaceCode = asString(body.replaceCode, 'replaceCode', { max: 32 }).trim().toUpperCase();
      const couple = findCoupleByCode(c.store, code);
      const codeDigest = sha256Hex(replaceCode);
      const memberByDirectCode = couple.members.find((m) => {
        if (m.replaceCodeDigest && digestsEqual(m.replaceCodeDigest, codeDigest)) return true;
        if (Array.isArray(m.replaceCodeDigests) && m.replaceCodeDigests.some((d) => digestsEqual(d, codeDigest))) return true;
        return false;
      });
      const pending = pendingReplace(couple);
      const hasPendingMatch = Boolean(pending && digestsEqual(pending.codeDigest, codeDigest));

      if (!memberByDirectCode && !hasPendingMatch) {
        throw httpError(403, 'bad_replace_code', 'Replace code is unknown, used or expired');
      }
      const member = memberByDirectCode ?? couple.members.find((m) => m.id === pending?.targetMemberId);
      if (!member) throw httpError(409, 'replace_target_missing', 'The member slot to replace no longer exists');
      if (hasPendingMatch && pending) pending.usedAt = nowIso();
      if (memberByDirectCode) {
        if (digestsEqual(member.replaceCodeDigest, codeDigest)) delete member.replaceCodeDigest;
        if (Array.isArray(member.replaceCodeDigests)) {
          member.replaceCodeDigests = member.replaceCodeDigests
            .filter((digest) => !digestsEqual(digest, codeDigest));
          if (member.replaceCodeDigests.length === 0) delete member.replaceCodeDigests;
        }
      }
      // The replaced slot gets a fresh start: old devices are cut off and the
      // old recovery key dies with them (a new one can be issued afterwards).
      revokeAllMemberSessions({
        store: c.store,
        realtime: c.realtime,
        push: c.push,
        couple,
        memberId: member.id,
      });
      delete member.recovery;
      if (body.name !== undefined) member.name = asString(body.name, 'name', { max: 100 });
      if (body.avatar !== undefined) member.avatar = asString(body.avatar, 'avatar', { max: 32 });
      if (body.color !== undefined) member.color = asString(body.color, 'color', { max: 32 });
      c.log(`pairing: member slot ${member.id} of couple ${couple.id} re-attached via replace code`);
      c.realtime.broadcastPartner(couple.id, member.id, 'partner_replaced', {
        member: serializeMember(couple, member, c.realtime),
      });
      const { record: replaceSession } = sessionResponse(c, couple, member, body, { rejoined: true, method: 'replaceCode' });
      notifySessionsChanged(c.realtime, couple.id, member.id, 'replaced', replaceSession);
      return;
    }

    throw httpError(400, 'missing_proof',
      'Provide one of: {code, recoveryKey}, {token}, or {code, replaceCode}');
  });

  // --- partner replace (approved by the remaining partner) -------------------

  // The remaining partner explicitly approves that the OTHER slot re-pairs on
  // a new device (lost phone, no recovery key). Single-use, 15-minute TTL.
  route('POST', '/api/couples/replace-partner', { auth: true }, (c) => {
    const partner = partnerOf(c.auth.couple, c.auth.memberId);
    if (!partner) throw httpError(409, 'no_partner', 'There is no partner slot to replace');
    if (pendingReplace(c.auth.couple)) {
      throw httpError(
        409,
        'replace_already_pending',
        'A partner replacement is already pending; cancel it before creating another code',
      );
    }
    const replaceCode = newReplaceCode();
    c.auth.couple.partnerReplace = {
      codeDigest: sha256Hex(replaceCode),
      targetMemberId: partner.id,
      createdBy: c.auth.memberId,
      createdAt: nowIso(),
      expiresAt: new Date(Date.now() + REPLACE_CODE_TTL_MS).toISOString(),
      usedAt: null,
    };
    c.store.markDirty();
    c.log(`pairing: replace code created for member ${partner.id} of couple ${c.auth.coupleId}`);
    sendJson(c.res, 201, {
      replaceCode,
      expiresAt: c.auth.couple.partnerReplace.expiresAt,
      target: serializeMember(c.auth.couple, partner, c.realtime),
    });
  });

  route('DELETE', '/api/couples/replace-partner', { auth: true }, (c) => {
    const cancelled = Boolean(pendingReplace(c.auth.couple));
    delete c.auth.couple.partnerReplace;
    c.store.markDirty();
    sendJson(c.res, 200, { ok: true, cancelled });
  });

  // --- device link codes (multi-device) --------------------------------------

  // A signed-in device mints a one-time, short-lived (10 min) code so a
  // SECOND device of the SAME member can attach without the recovery-key
  // ceremony. Issuing replaces any previous unconsumed code of the member.
  // `?format=qr` additionally renders a `sooodreamy://link` deep link as an
  // SVG QR code (admin rejoin-QR pattern) for camera hand-off.
  route('POST', '/api/sessions/link-code', { auth: true }, async (c) => {
    c.rateLimiter.consume('linkCodeCreate', requestKey(c.req));
    if (activeSessionCount(c.store, c.auth.coupleId, c.auth.memberId) >= MAX_SESSIONS_PER_MEMBER) {
      throw httpError(413, 'too_many_sessions',
        `This member already has ${MAX_SESSIONS_PER_MEMBER} active device sessions — revoke one first (POST /api/sessions/:id/revoke)`);
    }
    const body = await readJsonObject(c.req).catch(() => ({}));
    const wantsQr = c.url.searchParams.get('format') === 'qr';
    let server = null;
    if (wantsQr) {
      server = typeof body.server === 'string' && body.server.trim().length > 0
        ? body.server.trim()
        : requestBaseUrl(c.req, c.config.trustProxy);
      if (!/^https?:\/\/[^\s]+$/.test(server)) {
        throw httpError(400, 'bad_server_url', '"server" must be an http(s) base URL');
      }
      server = server.replace(/\/+$/, '');
    }
    const { linkCode, record } = issueLinkCode(c.store, {
      coupleId: c.auth.coupleId,
      memberId: c.auth.memberId,
    });
    c.store.markDirty();
    c.log(`pairing: device link code issued for member ${c.auth.memberId} of couple ${c.auth.coupleId}`);
    const response = {
      linkCode,
      expiresAt: record.expiresAt,
      createdAt: record.createdAt,
      memberId: c.auth.memberId,
    };
    if (wantsQr) {
      const deepLink = `sooodreamy://link?server=${encodeURIComponent(server)}&code=${encodeURIComponent(linkCode)}`;
      response.deepLink = deepLink;
      response.server = server;
      response.svg = await QRCode.toString(deepLink, {
        type: 'svg',
        errorCorrectionLevel: 'M',
        margin: 1,
        color: { dark: '#17062AFF', light: '#FFFFFFFF' },
      });
    }
    sendJson(c.res, 201, response);
  });

  // The NEW device redeems the code unauthenticated and receives a fresh
  // session for the SAME member slot. The code is burned only after every
  // check passed (a full session cap must not waste it) — validation and
  // consumption then happen in one synchronous step, so it stays atomically
  // single-use.
  route('POST', '/api/couples/link', { auth: false }, async (c) => {
    c.rateLimiter.consume('coupleLink', requestKey(c.req));
    const body = await readJsonObject(c.req);
    const code = asString(body.code, 'code', { max: 32 });
    const record = validateLinkCode(c.store, code);
    const couple = c.store.data.couples[record.coupleId];
    const member = couple?.members.find((candidate) => candidate.id === record.memberId);
    if (!member) {
      throw httpError(404, 'unknown_couple', 'The member slot of this device link code no longer exists');
    }
    if (activeSessionCount(c.store, couple.id, member.id) >= MAX_SESSIONS_PER_MEMBER) {
      throw httpError(413, 'too_many_sessions',
        `This member already has ${MAX_SESSIONS_PER_MEMBER} active device sessions — revoke one on a signed-in device first`);
    }
    record.consumedAt = nowIso();
    c.log(`pairing: member ${member.id} linked a new device to couple ${couple.id} via link code`);
    const { record: session } = sessionResponse(c, couple, member, body, { linked: true });
    // All of the member's existing devices learn about the newcomer (the new
    // device has no socket yet); the partner is deliberately NOT notified —
    // device management stays a per-member concern.
    c.realtime.sendToMember(couple.id, member.id, 'device_linked', {
      memberId: member.id,
      sessionId: session.sessionId,
      deviceId: session.deviceId,
      deviceName: session.deviceName,
      linkedAt: session.createdAt,
    }, { origin: sessionOrigin(session) });
    // Sync contract d: the generic session-lifecycle frame is sent IN
    // ADDITION to the richer device_linked (which stays for old clients).
    notifySessionsChanged(c.realtime, couple.id, member.id, 'linked', session);
  });
}
