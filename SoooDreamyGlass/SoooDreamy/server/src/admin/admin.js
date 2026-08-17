import crypto from 'node:crypto';
import path from 'node:path';
import { appendFile, readFile, readdir, rename, stat, unlink } from 'node:fs/promises';
import QRCode from 'qrcode';
import { httpError, nowIso, readJsonObject, sendJson, sha256Hex } from '../util.js';
import { invalidateLinkCodes, requestKey } from '../security.js';
import { issueRecoveryKey } from '../pairing.js';
import { createBackup, listBackups, pruneBackups } from '../backup.js';
import { allMessagesOf } from '../message-archive.js';
import { PASSWORD_WORDS } from './wordlist.js';

// ---------------------------------------------------------------------------
// v10.1 operator web panel, served by the app process at /admin.
//
// Security model:
// - The password is regenerated on EVERY boot (4 random words from a 256-word
//   list = 2^32 combinations) and printed ONLY to the server console. It is
//   never persisted and never returned by any API.
// - Login sets an httpOnly SameSite=Lax cookie scoped to Path=/admin; the
//   session lives in memory only (12 h sliding TTL) and dies with the process.
// - Logins are rate-limited per IP AND globally; every admin action is written
//   to an append-only audit file under DATA_DIR (admin-audit.log).
// - POST requests additionally verify the Origin header against the request
//   host (defense in depth on top of SameSite=Lax).
// ---------------------------------------------------------------------------

const SESSION_TTL_MS = 12 * 60 * 60 * 1000;
const SESSION_CAP = 32;
const QR_TOKEN_TTL_MS = 30 * 60 * 1000;
const COOKIE_NAME = 'sooodreamy_admin';
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const AUDIT_TAIL = 200;
const LOG_TAIL = 200;

const STATIC_FILES = Object.freeze({
  'admin.css': 'text/css; charset=utf-8',
  'admin.js': 'text/javascript; charset=utf-8',
});

export function generateAdminPassword() {
  return Array.from({ length: 4 }, () => PASSWORD_WORDS[crypto.randomInt(PASSWORD_WORDS.length)]).join('-');
}

function newReadableCode(length = 8) {
  let code = '';
  for (let i = 0; i < length; i++) code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  return code;
}

function digestsEqual(a, b) {
  const left = Buffer.from(String(a ?? ''));
  const right = Buffer.from(String(b ?? ''));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function parseCookies(header) {
  const cookies = {};
  for (const part of String(header ?? '').split(';')) {
    const eq = part.indexOf('=');
    if (eq === -1) continue;
    cookies[part.slice(0, eq).trim()] = part.slice(eq + 1).trim();
  }
  return cookies;
}

function isSecureRequest(req, trustProxy) {
  if (req.socket.encrypted === true) return true;
  return trustProxy === true && req.headers['x-forwarded-proto'] === 'https';
}

/** scheme://host of this request — the default server base URL for QR deep links. */
function requestBaseUrl(req, trustProxy) {
  const host = req.headers.host ?? 'localhost';
  return `${isSecureRequest(req, trustProxy) ? 'https' : 'http'}://${host}`;
}

export function createAdminPanel({
  store,
  realtime,
  push,
  rateLimiter,
  log = () => {},
  logBuffer = [],
  config = {},
}) {
  const password = generateAdminPassword();
  const passwordDigest = sha256Hex(password);
  const startedAt = nowIso();
  const sessions = new Map(); // token -> {createdAt, expiresAt, ip}
  const auditFile = path.join(store.dataDir, 'admin-audit.log');
  const auditMaxBytes = Math.max(1, Number(config.auditMaxBytes) || 5 * 1024 * 1024);
  const auditRetentionFiles = Math.max(1, Number(config.auditRetentionFiles) || 30);
  let auditChain = Promise.resolve();

  async function rotateAuditIfNeeded() {
    let info;
    try {
      info = await stat(auditFile);
    } catch (err) {
      if (err.code === 'ENOENT') return;
      throw err;
    }
    const today = new Date().toISOString().slice(0, 10);
    const fileDay = info.mtime.toISOString().slice(0, 10);
    if (info.size < auditMaxBytes && fileDay === today) return;
    const suffix = `${new Date().toISOString().replace(/[:.]/gu, '-')}-${crypto.randomBytes(4).toString('hex')}`;
    await rename(auditFile, path.join(store.dataDir, `admin-audit-${suffix}.log`));
    const rotated = (await readdir(store.dataDir, { withFileTypes: true }))
      .filter((entry) => entry.isFile() && /^admin-audit-.+\.log$/u.test(entry.name))
      .map((entry) => entry.name)
      .sort()
      .reverse();
    for (const name of rotated.slice(auditRetentionFiles)) {
      await unlink(path.join(store.dataDir, name));
    }
  }

  function audit(action, req, details = {}) {
    const entry = { at: nowIso(), action, ip: requestKey(req), ...details };
    auditChain = auditChain
      .catch(() => {})
      .then(async () => {
        await rotateAuditIfNeeded();
        await appendFile(auditFile, `${JSON.stringify(entry)}\n`, 'utf8');
      })
      .catch((err) => log('admin: audit write failed', err));
    return auditChain;
  }

  function pruneSessions() {
    const now = Date.now();
    for (const [token, session] of sessions) {
      if (Date.parse(session.expiresAt) <= now) sessions.delete(token);
    }
    while (sessions.size > SESSION_CAP) {
      const oldest = [...sessions.entries()].sort(
        (a, b) => a[1].createdAt.localeCompare(b[1].createdAt),
      )[0];
      sessions.delete(oldest[0]);
    }
  }

  function requireAdmin(req) {
    const token = parseCookies(req.headers.cookie)[COOKIE_NAME];
    const session = token ? sessions.get(token) : undefined;
    if (!session || Date.parse(session.expiresAt) <= Date.now()) {
      if (token) sessions.delete(token);
      throw httpError(401, 'admin_unauthorized', 'Admin login required');
    }
    // Sliding expiry: extend while the operator keeps using the panel.
    session.expiresAt = new Date(Date.now() + SESSION_TTL_MS).toISOString();
    return { token, session };
  }

  /** Defense in depth for state-changing requests, on top of SameSite=Lax. */
  function requireSameOrigin(req) {
    const origin = req.headers.origin;
    if (!origin || origin === 'null') return;
    let host;
    try {
      host = new URL(origin).host;
    } catch {
      throw httpError(403, 'admin_bad_origin', 'Malformed Origin header');
    }
    if (host !== (req.headers.host ?? '')) {
      throw httpError(403, 'admin_bad_origin', 'Cross-origin admin requests are not allowed');
    }
  }

  function setSessionCookie(req, res, token, maxAgeSeconds) {
    const attributes = [
      `${COOKIE_NAME}=${token}`,
      'Path=/admin',
      'HttpOnly',
      'SameSite=Lax',
      `Max-Age=${maxAgeSeconds}`,
    ];
    if (isSecureRequest(req, config.trustProxy)) attributes.push('Secure');
    res.setHeader('set-cookie', attributes.join('; '));
  }

  function coupleOr404(coupleId) {
    const couple = store.data.couples[coupleId];
    if (!couple) throw httpError(404, 'unknown_couple', 'No couple with this id');
    return couple;
  }

  function memberOr404(couple, memberId) {
    const member = couple.members.find((m) => m.id === memberId);
    if (!member) throw httpError(404, 'unknown_member', 'No member slot with this id in this couple');
    return member;
  }

  function sessionRecordsOf(coupleId) {
    return Object.entries(store.data.tokens)
      .filter(([, record]) => record.coupleId === coupleId)
      .map(([digest, record]) => ({ digest, record }));
  }

  function isLiveSession(record) {
    return !record.revokedAt && Date.parse(record.expiresAt) > Date.now();
  }

  function revokeRecord(record) {
    if (!record.revokedAt) record.revokedAt = nowIso();
    const couple = store.data.couples[record.coupleId];
    if (couple) {
      push.unregisterDevice({ store, couple, memberId: record.memberId, deviceId: record.deviceId });
    }
    // Sync contract d: the member's remaining devices refresh their device
    // manager (frame first, then the revoked sockets close with code 4001).
    realtime.sendToMember(record.coupleId, record.memberId, 'sessions_changed', {
      memberId: record.memberId,
      reason: 'revoked',
      sessionId: record.sessionId,
      deviceName: record.deviceName ?? null,
    });
    realtime.closeSession(record.sessionId, 'revoked by admin');
    store.markDirty();
  }

  // --- couple overview -------------------------------------------------------

  function memberAdminView(couple, member) {
    const records = Object.values(store.data.tokens)
      .filter((record) => record.coupleId === couple.id && record.memberId === member.id);
    const live = records.filter(isLiveSession);
    const appVersions = [...new Set(
      live
        .sort((a, b) => String(b.lastUsedAt).localeCompare(String(a.lastUsedAt)))
        .map((record) => record.userAgent)
        .filter(Boolean),
    )].slice(0, 3);
    return {
      id: member.id,
      name: member.name,
      avatar: member.avatar,
      color: member.color,
      online: realtime.isOnline(couple.id, member.id),
      lastSeenAt: member.lastSeenAt,
      joinedAt: member.joinedAt,
      sessions: records.length,
      activeSessions: live.length,
      appVersions,
      recoveryKeySetAt: member.recovery?.createdAt ?? null,
      hasReplaceCode: Boolean(member.replaceCodeDigest)
        || (Array.isArray(member.replaceCodeDigests) && member.replaceCodeDigests.length > 0),
    };
  }

  function coupleAdminView(couple) {
    const records = sessionRecordsOf(couple.id).map(({ record }) => record);
    const lastActivity = [
      ...couple.members.map((m) => m.lastSeenAt),
      ...records.map((r) => r.lastUsedAt),
    ].filter(Boolean).sort().pop() ?? null;
    const serialized = store.segmentFingerprints.get(couple.id);
    const quarantineFiles = store.quarantined.filter((entry) => entry.coupleId === couple.id);
    return {
      id: couple.id,
      code: couple.code,
      name: couple.name,
      createdAt: couple.createdAt,
      anniversary: couple.anniversary ?? null,
      members: couple.members.map((member) => memberAdminView(couple, member)),
      lastActiveAt: lastActivity,
      counts: {
        messages: allMessagesOf(couple).length,
        photos: couple.photos?.length ?? 0,
        videos: couple.videos?.length ?? 0,
        events: couple.events?.length ?? 0,
        games: couple.games?.length ?? 0,
        songs: couple.songs?.length ?? 0,
        coupons: couple.coupons?.length ?? 0,
      },
      segmentBytes: serialized ? Buffer.byteLength(serialized) : null,
      health: quarantineFiles.length > 0 ? 'recovered' : 'ok',
      quarantineFiles: quarantineFiles.map(({ file, reason, at }) => ({ file, reason, at })),
    };
  }

  function quarantinedView() {
    return [...store.quarantinedCoupleIds].map((coupleId) => ({
      id: coupleId,
      health: 'quarantined',
      files: store.quarantined
        .filter((entry) => entry.coupleId === coupleId)
        .map(({ file, reason, at }) => ({ file, reason, at })),
    }));
  }

  // --- API handlers ----------------------------------------------------------

  const api = {
    'POST /login': async (req, res) => {
      requireSameOrigin(req);
      rateLimiter.consume('adminLogin', requestKey(req));
      rateLimiter.consume('adminLoginGlobal', 'global');
      const body = await readJsonObject(req);
      const attempt = typeof body.password === 'string' ? body.password.trim() : '';
      if (!digestsEqual(sha256Hex(attempt), passwordDigest)) {
        audit('login_failed', req);
        log('admin: failed login attempt');
        throw httpError(403, 'admin_bad_password', 'Wrong admin password');
      }
      pruneSessions();
      const token = `adm_${crypto.randomBytes(24).toString('hex')}`;
      sessions.set(token, {
        createdAt: nowIso(),
        expiresAt: new Date(Date.now() + SESSION_TTL_MS).toISOString(),
        ip: requestKey(req),
      });
      setSessionCookie(req, res, token, Math.floor(SESSION_TTL_MS / 1000));
      audit('login', req);
      log('admin: operator logged in');
      sendJson(res, 200, { ok: true, name: config.name, version: config.version, startedAt });
    },

    'POST /logout': (req, res) => {
      requireSameOrigin(req);
      const { token } = requireAdmin(req);
      sessions.delete(token);
      setSessionCookie(req, res, 'gone', 0);
      audit('logout', req);
      sendJson(res, 200, { ok: true });
    },

    'GET /me': (req, res) => {
      requireAdmin(req);
      sendJson(res, 200, {
        ok: true,
        name: config.name,
        version: config.version,
        startedAt,
        serverTime: nowIso(),
      });
    },

    'GET /state': async (req, res) => {
      requireAdmin(req);
      const [storage, backups] = await Promise.all([
        store.storageStats(),
        listBackups(store.dataDir),
      ]);
      sendJson(res, 200, {
        server: {
          name: config.name,
          version: config.version,
          startedAt,
          serverTime: nowIso(),
          storage,
          backupIntervalMinutes: config.backupIntervalMinutes ?? null,
          latestBackup: backups[0] ?? null,
        },
        couples: Object.values(store.data.couples)
          .map((couple) => coupleAdminView(couple))
          .sort((a, b) => String(b.lastActiveAt ?? '').localeCompare(String(a.lastActiveAt ?? ''))),
        quarantined: quarantinedView(),
      });
    },

    'GET /couples/:coupleId/sessions': (req, res, params) => {
      requireAdmin(req);
      const couple = coupleOr404(params.coupleId);
      const memberNames = Object.fromEntries(couple.members.map((m) => [m.id, m.name]));
      const list = sessionRecordsOf(couple.id)
        .map(({ record }) => ({
          sessionId: record.sessionId,
          memberId: record.memberId,
          memberName: memberNames[record.memberId] ?? record.memberId,
          deviceId: record.deviceId,
          deviceName: record.deviceName,
          userAgent: record.userAgent ?? null,
          createdAt: record.createdAt,
          lastUsedAt: record.lastUsedAt,
          expiresAt: record.expiresAt,
          revokedAt: record.revokedAt,
          live: isLiveSession(record),
          kind: String(record.deviceId ?? '').startsWith('admin-qr-') ? 'adminQr' : 'device',
        }))
        .sort((a, b) => String(b.lastUsedAt).localeCompare(String(a.lastUsedAt)));
      sendJson(res, 200, { sessions: list });
    },

    'POST /couples/:coupleId/invite-code/reset': (req, res, params) => {
      requireSameOrigin(req);
      requireAdmin(req);
      const couple = coupleOr404(params.coupleId);
      const taken = new Set(Object.values(store.data.couples).map((c) => c.code));
      let code = couple.code;
      while (taken.has(code)) code = newReadableCode(6);
      const previous = couple.code;
      couple.code = code;
      store.markDirty();
      audit('invite_code_reset', req, { coupleId: couple.id });
      log(`admin: invite code of couple ${couple.id} reset (was ${previous})`);
      sendJson(res, 200, { code });
    },

    'POST /couples/:coupleId/members/:memberId/recovery-key/reset': (req, res, params) => {
      requireSameOrigin(req);
      requireAdmin(req);
      const couple = coupleOr404(params.coupleId);
      const member = memberOr404(couple, params.memberId);
      const recoveryKey = issueRecoveryKey(member);
      store.markDirty();
      audit('recovery_key_reset', req, { coupleId: couple.id, memberId: member.id });
      log(`admin: recovery key of member ${member.id} (couple ${couple.id}) reset`);
      sendJson(res, 200, { recoveryKey, createdAt: member.recovery.createdAt });
    },

    'POST /couples/:coupleId/members/:memberId/replace-code/reset': (req, res, params) => {
      requireSameOrigin(req);
      requireAdmin(req);
      const couple = coupleOr404(params.coupleId);
      const member = memberOr404(couple, params.memberId);
      const replaceCode = newReadableCode(8);
      // One canonical admin-issued code; older admin codes and member-chosen
      // custom codes are invalidated (that is the point of a reset).
      member.replaceCodeDigest = sha256Hex(replaceCode);
      delete member.replaceCodeDigests;
      store.markDirty();
      audit('replace_code_reset', req, { coupleId: couple.id, memberId: member.id });
      log(`admin: replace code for member ${member.id} (couple ${couple.id}) issued`);
      sendJson(res, 200, { replaceCode });
    },

    'POST /sessions/:sessionId/revoke': (req, res, params) => {
      requireSameOrigin(req);
      requireAdmin(req);
      const record = Object.values(store.data.tokens)
        .find((candidate) => candidate.sessionId === params.sessionId);
      if (!record) throw httpError(404, 'not_found', 'Unknown device session');
      revokeRecord(record);
      audit('session_revoked', req, {
        coupleId: record.coupleId,
        memberId: record.memberId,
        sessionId: record.sessionId,
      });
      log(`admin: session ${record.sessionId} revoked`);
      sendJson(res, 200, { ok: true });
    },

    'POST /couples/:coupleId/members/:memberId/sessions/revoke-all': (req, res, params) => {
      requireSameOrigin(req);
      requireAdmin(req);
      const couple = coupleOr404(params.coupleId);
      const member = memberOr404(couple, params.memberId);
      let revoked = 0;
      for (const record of Object.values(store.data.tokens)) {
        if (record.coupleId !== couple.id || record.memberId !== member.id) continue;
        if (record.revokedAt) continue;
        revokeRecord(record);
        revoked += 1;
      }
      // Revoking every device also voids pending device link codes — the
      // operator's cut-off must not leave a self-service door open.
      if (invalidateLinkCodes(store, { coupleId: couple.id, memberId: member.id }) > 0) {
        store.markDirty();
      }
      audit('sessions_revoked_all', req, { coupleId: couple.id, memberId: member.id, revoked });
      log(`admin: ${revoked} session(s) of member ${member.id} (couple ${couple.id}) revoked`);
      sendJson(res, 200, { ok: true, revoked });
    },

    'POST /couples/:coupleId/members/:memberId/rejoin-qr': async (req, res, params) => {
      requireSameOrigin(req);
      requireAdmin(req);
      const couple = coupleOr404(params.coupleId);
      const member = memberOr404(couple, params.memberId);
      const body = await readJsonObject(req).catch(() => ({}));
      let server = typeof body.server === 'string' && body.server.trim().length > 0
        ? body.server.trim()
        : requestBaseUrl(req, config.trustProxy);
      if (!/^https?:\/\/[^\s]+$/.test(server)) {
        throw httpError(400, 'bad_server_url', '"server" must be an http(s) base URL');
      }
      server = server.replace(/\/+$/, '');
      // This is a dedicated, one-time nonce — never a bearer session. Keeping
      // it in a separate index means Authorization: Bearer <QR> always fails.
      const token = `qr_${crypto.randomBytes(24).toString('hex')}`;
      const nonceId = `qrn_${crypto.randomBytes(8).toString('hex')}`;
      const record = {
        id: nonceId,
        coupleId: couple.id,
        memberId: member.id,
        createdAt: nowIso(),
        expiresAt: new Date(Date.now() + QR_TOKEN_TTL_MS).toISOString(),
        consumedAt: null,
      };
      store.data.qrNonces ??= {};
      store.data.qrNonces[sha256Hex(token)] = record;
      store.markDirty();
      const deepLink = `sooodreamy://rejoin?server=${encodeURIComponent(server)}&token=${encodeURIComponent(token)}`;
      const svg = await QRCode.toString(deepLink, {
        type: 'svg',
        errorCorrectionLevel: 'M',
        margin: 1,
        color: { dark: '#17062AFF', light: '#FFFFFFFF' },
      });
      audit('rejoin_qr_issued', req, {
        coupleId: couple.id,
        memberId: member.id,
        nonceId,
      });
      log(`admin: rejoin QR for member ${member.id} (couple ${couple.id}) issued`);
      sendJson(res, 200, {
        deepLink,
        svg,
        server,
        expiresAt: record.expiresAt,
        nonceId,
        memberId: member.id,
      });
    },

    'GET /backups': async (req, res) => {
      requireAdmin(req);
      const backups = await listBackups(store.dataDir);
      sendJson(res, 200, {
        backups: backups.slice(0, 20),
        total: backups.length,
        intervalMinutes: config.backupIntervalMinutes ?? null,
      });
    },

    'POST /backups': async (req, res) => {
      requireSameOrigin(req);
      requireAdmin(req);
      await store.flush();
      const backup = await createBackup({
        dataDir: store.dataDir,
        reason: 'admin',
        includeMedia: config.backupIncludeMedia !== false,
        log,
      });
      await pruneBackups({ dataDir: store.dataDir, log });
      audit('backup_created', req, { backupId: backup?.id ?? null });
      sendJson(res, 200, { ok: true, backup });
    },

    'GET /logs': (req, res) => {
      requireAdmin(req);
      sendJson(res, 200, { lines: logBuffer.slice(-LOG_TAIL) });
    },

    'GET /audit': async (req, res) => {
      requireAdmin(req);
      // Read-your-own-writes: appends run on a promise chain, so an action
      // performed a moment ago may still be in flight — drain it first.
      await auditChain.catch(() => {});
      let raw = '';
      try {
        raw = await readFile(auditFile, 'utf8');
      } catch (err) {
        if (err.code !== 'ENOENT') throw err;
      }
      const entries = raw
        .split('\n')
        .filter(Boolean)
        .slice(-AUDIT_TAIL)
        .map((line) => {
          try {
            return JSON.parse(line);
          } catch {
            return { at: null, action: 'unparseable', raw: line.slice(0, 200) };
          }
        })
        .reverse();
      sendJson(res, 200, { entries });
    },
  };

  const apiRoutes = Object.entries(api).map(([key, handler]) => {
    const [method, pattern] = key.split(' ');
    return { method, segments: pattern.split('/').filter(Boolean), handler };
  });

  function matchApi(method, segments) {
    for (const route of apiRoutes) {
      if (route.method !== method || route.segments.length !== segments.length) continue;
      const params = {};
      let ok = true;
      for (let i = 0; i < segments.length; i++) {
        const expected = route.segments[i];
        if (expected.startsWith(':')) params[expected.slice(1)] = decodeURIComponent(segments[i]);
        else if (expected !== segments[i]) {
          ok = false;
          break;
        }
      }
      if (ok) return { handler: route.handler, params };
    }
    return null;
  }

  async function serveStatic(res, name) {
    const contentType = name === 'index.html'
      ? 'text/html; charset=utf-8'
      : STATIC_FILES[name];
    if (!contentType) throw httpError(404, 'not_found', 'Unknown admin asset');
    let body;
    try {
      body = await readFile(new URL(`./public/${name}`, import.meta.url));
    } catch {
      throw httpError(404, 'not_found', 'Admin asset missing');
    }
    res.writeHead(200, {
      'content-type': contentType,
      'content-length': body.length,
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
      ...(name === 'index.html' ? {
        'content-security-policy':
          "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; "
          + "connect-src 'self'; base-uri 'none'; frame-ancestors 'none'",
        'referrer-policy': 'no-referrer',
      } : {}),
    });
    res.end(body);
  }

  /** Handles every request whose path is /admin or /admin/… (called by the router). */
  async function handle(req, res, url) {
    const segments = url.pathname.split('/').filter(Boolean); // ['admin', ...]
    if (segments.length === 1) {
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        throw httpError(404, 'not_found', 'The admin panel is served at GET /admin');
      }
      await serveStatic(res, 'index.html');
      return;
    }
    if (segments[1] === 'assets' && segments.length === 3 && req.method === 'GET') {
      await serveStatic(res, segments[2]);
      return;
    }
    if (segments[1] === 'api') {
      const match = matchApi(req.method, segments.slice(2));
      if (!match) throw httpError(404, 'not_found', `No admin route for ${req.method} ${url.pathname}`);
      await match.handler(req, res, match.params);
      return;
    }
    throw httpError(404, 'not_found', `No admin route for ${req.method} ${url.pathname}`);
  }

  return {
    password,
    startedAt,
    handle,
    /** Test/diagnostics helper: number of live admin sessions. */
    get sessionCount() {
      pruneSessions();
      return sessions.size;
    },
    async close() {
      await auditChain.catch(() => {});
    },
  };
}
