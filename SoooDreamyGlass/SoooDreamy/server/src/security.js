import { createHash, randomInt, timingSafeEqual } from 'node:crypto';
import { httpError, id, newToken, nowIso } from './util.js';

const DEFAULT_SESSION_TTL_MS = 90 * 24 * 60 * 60 * 1000;
export const SESSION_REJOIN_GRACE_MS = 24 * 60 * 60 * 1000;
const REVOKED_SESSION_RETENTION_MS = 24 * 60 * 60 * 1000;
const QR_NONCE_RETENTION_MS = 24 * 60 * 60 * 1000;
const LINK_CODE_TTL_MS = 10 * 60 * 1000;
const LINK_CODE_RETENTION_MS = 24 * 60 * 60 * 1000;
// Same unambiguous alphabet as couple/replace codes (no 0/O/1/I).
const LINK_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const LINK_CODE_LENGTH = 8;
export const MAX_SESSIONS_PER_MEMBER = 8;
const MAX_RATE_KEYS = 10_000;

const RATE_POLICIES = Object.freeze({
  coupleCreate: { limit: 5, windowMs: 60 * 60 * 1000 },
  coupleJoin: { limit: 20, windowMs: 60 * 60 * 1000 },
  coupleRejoin: { limit: 30, windowMs: 60 * 60 * 1000 },
  // Multi-device: issuing device link codes is authenticated but still
  // bounded; redeeming is unauthenticated and gets the coupleJoin budget.
  linkCodeCreate: { limit: 10, windowMs: 15 * 60 * 1000 },
  coupleLink: { limit: 20, windowMs: 60 * 60 * 1000 },
  gameCreate: { limit: 20, windowMs: 60 * 1000 },
  gameMove: { limit: 240, windowMs: 60 * 1000 },
  // v10.1 admin panel: the per-boot password is guarded by a strict per-IP
  // limit plus a global cap (so a botnet cannot multiply the attempt budget).
  adminLogin: { limit: 10, windowMs: 15 * 60 * 1000 },
  adminLoginGlobal: { limit: 100, windowMs: 15 * 60 * 1000 },
});

function cleanIp(value) {
  if (typeof value !== 'string') return '';
  const first = value.split(',')[0].trim();
  return first.startsWith('::ffff:') ? first.slice(7) : first;
}

export function isPrivateAddress(value) {
  const ip = cleanIp(value);
  if (ip === '::1' || ip === 'localhost') return true;
  if (/^10\./.test(ip) || /^192\.168\./.test(ip) || /^127\./.test(ip) || /^169\.254\./.test(ip)) return true;
  const second = /^172\.(\d+)\./.exec(ip);
  if (second && Number(second[1]) >= 16 && Number(second[1]) <= 31) return true;
  const cgnat = /^100\.(\d+)\./.exec(ip);
  if (cgnat && Number(cgnat[1]) >= 64 && Number(cgnat[1]) <= 127) return true;
  return /^f[cd][0-9a-f]{2}:/i.test(ip) || /^fe[89ab][0-9a-f]:/i.test(ip);
}

export function requireSecureTransport(req, {
  allowInsecurePrivateLAN = false,
  allowInsecureHttp = false,
  trustProxy = false,
} = {}) {
  const forwardedProto = trustProxy ? req.headers['x-forwarded-proto'] : null;
  const secure = req.socket.encrypted === true || forwardedProto === 'https';
  if (secure) return;
  if (allowInsecureHttp) return;
  if (allowInsecurePrivateLAN && isPrivateAddress(req.socket.remoteAddress)) return;
  throw httpError(
    426,
    'https_required',
    'HTTP is rejected in this transport mode. Remove REQUIRE_HTTPS=1 or use ALLOW_HTTP_PRIVATE_LAN=1 from a private address.',
  );
}

export function requestKey(req) {
  return cleanIp(req.socket.remoteAddress) || 'unknown';
}

export class RateLimiter {
  constructor({ now = () => Date.now(), policies = RATE_POLICIES } = {}) {
    this.now = now;
    this.policies = policies;
    this.buckets = new Map();
  }

  consume(scope, key) {
    const policy = this.policies[scope];
    if (!policy) return;
    const now = this.now();
    const bucketKey = `${scope}:${key}`;
    let bucket = this.buckets.get(bucketKey);
    if (!bucket || now >= bucket.resetAt) {
      bucket = { count: 0, resetAt: now + policy.windowMs, touchedAt: now };
      this.buckets.set(bucketKey, bucket);
    }
    bucket.count += 1;
    bucket.touchedAt = now;
    this.#trim(now);
    if (bucket.count > policy.limit) {
      const retryAfter = Math.max(1, Math.ceil((bucket.resetAt - now) / 1000));
      const err = httpError(429, 'rate_limited', `Too many ${scope} requests; retry in ${retryAfter}s`);
      err.retryAfter = retryAfter;
      throw err;
    }
  }

  #trim(now) {
    if (this.buckets.size <= MAX_RATE_KEYS) return;
    for (const [key, bucket] of this.buckets) {
      if (now >= bucket.resetAt) this.buckets.delete(key);
      if (this.buckets.size <= MAX_RATE_KEYS) return;
    }
    const oldest = [...this.buckets.entries()].sort((a, b) => a[1].touchedAt - b[1].touchedAt);
    for (const [key] of oldest.slice(0, this.buckets.size - MAX_RATE_KEYS)) this.buckets.delete(key);
  }
}

export function tokenDigest(token) {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}

/**
 * Non-sensitive origin marker for WS frames: which member/device (and which
 * session, abbreviated) caused an event. Deliberately NEVER contains tokens
 * or digests — deviceId is fine inside the couple, and the 8-char session
 * suffix only lets a client recognize itself, not act on another session.
 */
export function sessionOrigin(record) {
  return {
    memberId: record.memberId,
    deviceId: record.deviceId,
    sessionSuffix: String(record.sessionId ?? '').slice(-8),
  };
}

function safeEqualText(a, b) {
  const left = Buffer.from(String(a));
  const right = Buffer.from(String(b));
  return left.length === right.length && timingSafeEqual(left, right);
}

function normalizeDeviceId(value) {
  if (typeof value !== 'string') return id('device');
  const clean = value.trim();
  return clean.length >= 8 && clean.length <= 128 ? clean : id('device');
}

function normalizeDeviceName(value) {
  if (typeof value !== 'string') return 'Unknown device';
  const clean = value.trim();
  return clean.length > 0 ? clean.slice(0, 100) : 'Unknown device';
}

export function createSession(store, {
  coupleId,
  memberId,
  deviceId,
  deviceName,
  ttlMs = DEFAULT_SESSION_TTL_MS,
} = {}) {
  const token = newToken();
  const createdAt = nowIso();
  const record = {
    sessionId: id('session'),
    coupleId,
    memberId,
    deviceId: normalizeDeviceId(deviceId),
    deviceName: normalizeDeviceName(deviceName),
    createdAt,
    lastUsedAt: createdAt,
    expiresAt: new Date(Date.now() + ttlMs).toISOString(),
    revokedAt: null,
  };
  const digest = tokenDigest(token);
  store.data.tokens[digest] = record;
  trimMemberSessions(store, coupleId, memberId, digest);
  return { token, record };
}

/** True once a session record can no longer authenticate (revoked or expired). */
function isDeadSessionRecord(record, now = Date.now()) {
  if (record.revokedAt) return true;
  const expiresAt = Date.parse(record.expiresAt);
  return !Number.isFinite(expiresAt) || expiresAt <= now;
}

/**
 * Eviction order for the per-member session ceiling: retained dead records
 * (revoked/expired, kept briefly for rejoin/forensics) go first, then the
 * oldest live sessions. With up to 8 real devices per member, a stale record
 * must never silently evict someone's active phone.
 */
function sessionEvictionSort(entries, keepDigest, now = Date.now()) {
  const rank = ([digest, record]) => {
    if (digest === keepDigest) return 2;
    return isDeadSessionRecord(record, now) ? 0 : 1;
  };
  return entries.sort((left, right) => rank(right) - rank(left)
    || String(right[1].createdAt).localeCompare(String(left[1].createdAt)));
}

function trimMemberSessions(store, coupleId, memberId, keepDigest) {
  const records = sessionEvictionSort(
    Object.entries(store.data.tokens)
      .filter(([, record]) => record.coupleId === coupleId && record.memberId === memberId),
    keepDigest,
  );
  for (const [digest] of records.slice(MAX_SESSIONS_PER_MEMBER)) {
    delete store.data.tokens[digest];
  }
}

/** Live (neither revoked nor expired) sessions of one member. */
export function activeSessionCount(store, coupleId, memberId, now = Date.now()) {
  return Object.values(store.data.tokens).filter((record) =>
    record.coupleId === coupleId
    && record.memberId === memberId
    && !isDeadSessionRecord(record, now)).length;
}

/**
 * True while a session (by id) can still authenticate for that member. The
 * game input lease dies lazily with its session — a lease held by a revoked,
 * expired or evicted session must not lock the member out of their own game.
 */
export function isSessionLive(store, memberId, sessionId, now = Date.now()) {
  for (const record of Object.values(store.data.tokens)) {
    if (record.sessionId === sessionId && record.memberId === memberId) {
      return !isDeadSessionRecord(record, now);
    }
  }
  return false;
}

/**
 * Removes security proofs that are no longer usable and enforces the
 * per-member session ceiling. Returns the number of removed records.
 */
export function cleanupSessions(store, { now = Date.now() } = {}) {
  let removed = 0;
  for (const [digest, record] of Object.entries(store.data.tokens)) {
    const expiresAt = Date.parse(record.expiresAt);
    const revokedAt = Date.parse(record.revokedAt ?? '');
    const beyondExpiryGrace = !Number.isFinite(expiresAt)
      || expiresAt + SESSION_REJOIN_GRACE_MS <= now;
    const beyondRevokedRetention = record.revokedAt
      && (!Number.isFinite(revokedAt) || revokedAt + REVOKED_SESSION_RETENTION_MS <= now);
    if (beyondExpiryGrace || beyondRevokedRetention) {
      delete store.data.tokens[digest];
      removed += 1;
    }
  }

  const groups = new Map();
  for (const [digest, record] of Object.entries(store.data.tokens)) {
    const key = `${record.coupleId}\0${record.memberId}`;
    const group = groups.get(key) ?? [];
    group.push([digest, record]);
    groups.set(key, group);
  }
  for (const records of groups.values()) {
    sessionEvictionSort(records, null, now);
    for (const [digest] of records.slice(MAX_SESSIONS_PER_MEMBER)) {
      delete store.data.tokens[digest];
      removed += 1;
    }
  }

  for (const [digest, record] of Object.entries(store.data.qrNonces ?? {})) {
    const terminalAt = Date.parse(record.consumedAt ?? record.expiresAt);
    if (!Number.isFinite(terminalAt) || terminalAt + QR_NONCE_RETENTION_MS <= now) {
      delete store.data.qrNonces[digest];
      removed += 1;
    }
  }

  for (const [digest, record] of Object.entries(store.data.linkCodes ?? {})) {
    const terminalAt = Date.parse(record.consumedAt ?? record.expiresAt);
    if (!Number.isFinite(terminalAt) || terminalAt + LINK_CODE_RETENTION_MS <= now) {
      delete store.data.linkCodes[digest];
      removed += 1;
    }
  }
  if (removed > 0) store.markDirty();
  return removed;
}

// ---------------------------------------------------------------------------
// Device link codes (multi-device): a signed-in device mints a one-time,
// short-lived code so a SECOND device of the SAME member can attach without
// the recovery-key ceremony. Stored hashed (SHA-256 digest key) like every
// other proof; the plaintext leaves the server exactly once.

function newLinkCode() {
  let code = '';
  for (let i = 0; i < LINK_CODE_LENGTH; i++) {
    code += LINK_CODE_ALPHABET[randomInt(LINK_CODE_ALPHABET.length)];
  }
  return code;
}

export function normalizeLinkCode(value) {
  return String(value ?? '').trim().toUpperCase();
}

/**
 * Issues a fresh device link code for one member. Any previous unconsumed
 * code of that member is invalidated (exactly one pending code per member —
 * the admin-reset pattern). Returns the plaintext code plus its record.
 */
export function issueLinkCode(store, { coupleId, memberId }) {
  invalidateLinkCodes(store, { coupleId, memberId, pendingOnly: true });
  const linkCode = newLinkCode();
  const record = {
    coupleId,
    memberId,
    // One clock read for both stamps: two separate Date.now() calls made
    // expiresAt-createdAt drift to TTL+1ms on slow runners (CI flake).
    ...(() => {
      const minted = Date.now();
      return {
        createdAt: new Date(minted).toISOString(),
        expiresAt: new Date(minted + LINK_CODE_TTL_MS).toISOString(),
      };
    })(),
    consumedAt: null,
  };
  if (!store.data.linkCodes) store.data.linkCodes = {};
  store.data.linkCodes[tokenDigest(linkCode)] = record;
  return { linkCode, record };
}

/**
 * Validates a device link code and returns its live record WITHOUT consuming
 * it — the route consumes (`consumedAt`) synchronously right before minting
 * the session, so a legitimate later failure (full session cap) does not
 * burn the code. Throws precise, documented errors: 403 bad_link_code
 * (unknown), 403 link_code_expired, 409 link_code_consumed (single-use).
 */
export function validateLinkCode(store, code) {
  const record = store.data.linkCodes?.[tokenDigest(normalizeLinkCode(code))];
  if (!record) {
    throw httpError(403, 'bad_link_code', 'This device link code is unknown — codes are 8 characters and case-insensitive');
  }
  if (record.consumedAt) {
    throw httpError(409, 'link_code_consumed', 'This device link code was already used — ask your signed-in device for a new one');
  }
  if (Date.parse(record.expiresAt) <= Date.now()) {
    throw httpError(403, 'link_code_expired', 'This device link code has expired — ask your signed-in device for a new one');
  }
  return record;
}

/**
 * Drops link codes of a couple (or one member). Called when all sessions of
 * a member are cut off (partner replace, admin revoke-all) and on couple
 * dissolve — a pending link code must never outlive that intent. With
 * `pendingOnly` the consumed history entries are kept for their retention.
 */
export function invalidateLinkCodes(store, { coupleId, memberId = null, pendingOnly = false }) {
  let removed = 0;
  for (const [digest, record] of Object.entries(store.data.linkCodes ?? {})) {
    if (record.coupleId !== coupleId) continue;
    if (memberId !== null && record.memberId !== memberId) continue;
    if (pendingOnly && record.consumedAt) continue;
    delete store.data.linkCodes[digest];
    removed += 1;
  }
  return removed;
}

function migrateLegacyRecord(store, rawToken, record) {
  const digest = tokenDigest(rawToken);
  if (store.data.tokens[digest]) return store.data.tokens[digest];
  const now = nowIso();
  const migrated = {
    ...record,
    sessionId: record.sessionId ?? id('session'),
    deviceId: record.deviceId ?? 'legacy-device',
    deviceName: record.deviceName ?? 'Legacy device',
    createdAt: record.createdAt ?? now,
    lastUsedAt: record.lastUsedAt ?? now,
    expiresAt: record.expiresAt ?? new Date(Date.now() + DEFAULT_SESSION_TTL_MS).toISOString(),
    revokedAt: record.revokedAt ?? null,
  };
  store.data.tokens[digest] = migrated;
  delete store.data.tokens[rawToken];
  store.markDirty();
  return migrated;
}

/** True when a token-store key already is a SHA-256 digest (v4.0+ format). */
export function isDigestKey(key) {
  return /^[0-9a-f]{64}$/.test(key);
}

/**
 * Eagerly upgrades every legacy raw-token entry ({<rawToken>: {coupleId,
 * memberId}}, pre-4.0) to a digest-keyed session record. The lazy per-request
 * path (migrateLegacyRecord) stays for stragglers; this exists so
 * `npm run migrate` leaves a fully current token store. Returns the count.
 */
export function upgradeLegacyTokens(store) {
  let upgraded = 0;
  for (const [key, record] of Object.entries({ ...store.data.tokens })) {
    if (isDigestKey(key)) {
      if (!record.sessionId) {
        // Digest key with incomplete record — fill in the session fields.
        store.data.tokens[key] = {
          ...record,
          sessionId: record.sessionId ?? id('session'),
          deviceId: record.deviceId ?? 'legacy-device',
          deviceName: record.deviceName ?? 'Legacy device',
          createdAt: record.createdAt ?? nowIso(),
          lastUsedAt: record.lastUsedAt ?? nowIso(),
          expiresAt: record.expiresAt ?? new Date(Date.now() + DEFAULT_SESSION_TTL_MS).toISOString(),
          revokedAt: record.revokedAt ?? null,
        };
        store.markDirty();
        upgraded += 1;
      }
      continue;
    }
    migrateLegacyRecord(store, key, record);
    upgraded += 1;
  }
  return upgraded;
}

export function authenticateToken(store, token, { touch = true, userAgent = null } = {}) {
  if (typeof token !== 'string' || token.length < 16) return null;
  const digest = tokenDigest(token);
  let record = store.data.tokens[digest];
  if (!record && store.data.tokens[token]) record = migrateLegacyRecord(store, token, store.data.tokens[token]);
  if (!record || record.revokedAt || Date.parse(record.expiresAt) <= Date.now()) return null;
  const couple = store.data.couples[record.coupleId];
  // Damaged-on-disk couples get an honest 503 instead of a misleading 401:
  // the session IS valid, the data needs an operator restore (npm run restore).
  if (!couple && store.quarantinedCoupleIds?.has(record.coupleId)) {
    throw httpError(503, 'couple_data_quarantined',
      'This couple\u2019s data was damaged on disk and moved to quarantine. '
      + 'The server operator can bring it back with a backup restore (npm run restore).');
  }
  const member = couple?.members.find((candidate) => candidate.id === record.memberId);
  if (!member) return null;
  if (touch) {
    const stale = Date.now() - Date.parse(record.lastUsedAt ?? 0) > 5 * 60 * 1000;
    // The client's User-Agent ("SoooDreamy/47 CFNetwork/…") doubles as the
    // per-device app version shown in the admin panel. It changes only when
    // the app updates, so writing on change adds no meaningful I/O on top of
    // the throttled lastUsedAt touch.
    const agent = userAgent ? String(userAgent).slice(0, 160) : null;
    const agentChanged = agent !== null && record.userAgent !== agent;
    if (stale || agentChanged) {
      if (stale) record.lastUsedAt = nowIso();
      if (agent !== null) record.userAgent = agent;
      store.markDirty();
    }
  }
  return { record, couple, member };
}

export function rotateSession(store, token) {
  const auth = authenticateToken(store, token, { touch: false });
  if (!auth) throw httpError(401, 'invalid_token', 'Unknown or expired token');
  const nextToken = newToken();
  const oldDigest = tokenDigest(token);
  const record = {
    ...auth.record,
    lastUsedAt: nowIso(),
    expiresAt: new Date(Date.now() + DEFAULT_SESSION_TTL_MS).toISOString(),
  };
  store.data.tokens[tokenDigest(nextToken)] = record;
  delete store.data.tokens[oldDigest];
  store.markDirty();
  return { token: nextToken, record };
}

export function revokeSession(store, sessionId, memberId) {
  for (const record of Object.values(store.data.tokens)) {
    if (record.sessionId === sessionId && record.memberId === memberId) {
      if (!record.revokedAt) record.revokedAt = nowIso();
      store.markDirty();
      return true;
    }
  }
  return false;
}

export function sessionView(record, currentSessionId) {
  return {
    id: record.sessionId,
    deviceId: record.deviceId,
    deviceName: record.deviceName,
    createdAt: record.createdAt,
    lastUsedAt: record.lastUsedAt,
    expiresAt: record.expiresAt,
    revokedAt: record.revokedAt,
    current: safeEqualText(record.sessionId, currentSessionId),
  };
}

export function sanitizeLogValue(value) {
  const text = String(value ?? '');
  return text
    .replace(/([?&](?:token|access_token)=)[^&\s]+/gi, '$1[REDACTED]')
    .replace(/(Bearer\s+)[A-Za-z0-9._~-]+/gi, '$1[REDACTED]')
    .slice(0, 2_000);
}
