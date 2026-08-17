import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { client, makeApp, setupCouple } from './helpers.js';

// v10.1 operator web panel (/admin): per-boot password, cookie session,
// rate-limited login, audited admin actions — see docs/ADMIN-PANEL.md.

/** Logs into the panel and returns a fetch wrapper that carries the cookie. */
async function adminLogin(ctx) {
  const response = await fetch(`${ctx.baseUrl}/admin/api/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ password: ctx.app.admin.password }),
  });
  assert.equal(response.status, 200);
  const setCookie = response.headers.get('set-cookie');
  assert.ok(setCookie, 'login must set the session cookie');
  const cookie = setCookie.split(';')[0];
  async function req(method, pathname, json) {
    const res = await fetch(`${ctx.baseUrl}/admin/api${pathname}`, {
      method,
      headers: { cookie, ...(json === undefined ? {} : { 'content-type': 'application/json' }) },
      body: json === undefined ? undefined : JSON.stringify(json),
    });
    const type = res.headers.get('content-type') ?? '';
    return { status: res.status, body: type.includes('json') ? await res.json() : await res.text() };
  }
  return { cookie, setCookie, get: (p) => req('GET', p), post: (p, j) => req('POST', p, j) };
}

test('admin password rotates on every boot and is four typable word groups', async (t) => {
  const first = await makeApp(t);
  const second = await makeApp(t);
  for (const ctx of [first, second]) {
    assert.match(ctx.app.admin.password, /^[a-z]{2,10}(-[a-z]{2,10}){3}$/,
      'password is 4 lowercase word groups joined by dashes');
  }
  assert.notEqual(first.app.admin.password, second.app.admin.password,
    'every boot generates a fresh password');
});

test('GET /admin serves the login page without auth; assets are whitelisted', async (t) => {
  const { baseUrl } = await makeApp(t);
  const page = await fetch(`${baseUrl}/admin`);
  assert.equal(page.status, 200);
  assert.match(page.headers.get('content-type'), /text\/html/);
  assert.match(page.headers.get('content-security-policy'), /default-src 'self'/);
  assert.equal(page.headers.get('access-control-allow-origin'), null);
  assert.match(await page.text(), /SoooDreamy/);

  const css = await fetch(`${baseUrl}/admin/assets/admin.css`);
  assert.equal(css.status, 200);
  assert.match(css.headers.get('content-type'), /text\/css/);
  const script = await fetch(`${baseUrl}/admin/assets/admin.js`);
  assert.equal(script.status, 200);

  const traversal = await fetch(`${baseUrl}/admin/assets/..%2Fadmin.js`);
  assert.equal(traversal.status, 404, 'only whitelisted asset names are served');
  const unknown = await fetch(`${baseUrl}/admin/assets/wordlist.js`);
  assert.equal(unknown.status, 404);
});

test('login: wrong password 403, right password sets a hardened cookie', async (t) => {
  const ctx = await makeApp(t);
  const wrong = await fetch(`${ctx.baseUrl}/admin/api/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ password: 'wolke-herz-funke-falsch' }),
  });
  assert.equal(wrong.status, 403);
  assert.equal((await wrong.json()).error, 'admin_bad_password');

  const admin = await adminLogin(ctx);
  assert.match(admin.setCookie, /HttpOnly/i);
  assert.match(admin.setCookie, /SameSite=Lax/i);
  assert.match(admin.setCookie, /Path=\/admin/i);

  const me = await admin.get('/me');
  assert.equal(me.status, 200);
  assert.equal(me.body.ok, true);
  assert.equal(typeof me.body.version, 'string');
});

test('every admin API requires the session cookie', async (t) => {
  const { baseUrl } = await makeApp(t);
  const paths = [
    ['GET', '/admin/api/me'],
    ['GET', '/admin/api/state'],
    ['GET', '/admin/api/couples/c_x/sessions'],
    ['GET', '/admin/api/logs'],
    ['GET', '/admin/api/audit'],
    ['GET', '/admin/api/backups'],
    ['POST', '/admin/api/logout'],
    ['POST', '/admin/api/backups'],
    ['POST', '/admin/api/couples/c_x/invite-code/reset'],
    ['POST', '/admin/api/couples/c_x/members/m_x/recovery-key/reset'],
    ['POST', '/admin/api/couples/c_x/members/m_x/replace-code/reset'],
    ['POST', '/admin/api/couples/c_x/members/m_x/sessions/revoke-all'],
    ['POST', '/admin/api/couples/c_x/members/m_x/rejoin-qr'],
    ['POST', '/admin/api/sessions/s_x/revoke'],
  ];
  for (const [method, pathname] of paths) {
    const response = await fetch(baseUrl + pathname, { method });
    assert.equal(response.status, 401, `${method} ${pathname} must be locked`);
    assert.equal((await response.json()).error, 'admin_unauthorized');
  }
});

test('login is rate-limited per IP after 10 attempts', async (t) => {
  const { baseUrl } = await makeApp(t);
  let last = null;
  for (let i = 0; i < 11; i++) {
    last = await fetch(`${baseUrl}/admin/api/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ password: `guess-${i}` }),
    });
  }
  assert.equal(last.status, 429);
  const body = await last.json();
  assert.equal(body.error, 'rate_limited');
  assert.ok(Number(last.headers.get('retry-after')) >= 1);
});

test('cross-origin POSTs are rejected even with a valid cookie', async (t) => {
  const ctx = await makeApp(t);
  const admin = await adminLogin(ctx);
  const response = await fetch(`${ctx.baseUrl}/admin/api/backups`, {
    method: 'POST',
    headers: { cookie: admin.cookie, origin: 'https://evil.example' },
  });
  assert.equal(response.status, 403);
  assert.equal((await response.json()).error, 'admin_bad_origin');
});

test('logout invalidates the admin session immediately', async (t) => {
  const ctx = await makeApp(t);
  const admin = await adminLogin(ctx);
  assert.equal((await admin.post('/logout')).status, 200);
  assert.equal((await admin.get('/me')).status, 401);
});

test('state lists couples with members, activity, app versions and data counts', async (t) => {
  const ctx = await makeApp(t);
  const pair = await setupCouple(ctx.baseUrl);
  await pair.a.api.post('/api/messages', { json: { type: 'text', text: 'hi schatz' } });
  // The iOS client's User-Agent doubles as the app-version display.
  await fetch(`${ctx.baseUrl}/api/couple`, {
    headers: { authorization: `Bearer ${pair.a.token}`, 'user-agent': 'SoooDreamy/47 CFNetwork/1490 Darwin/23' },
  });

  const admin = await adminLogin(ctx);
  const state = await admin.get('/state');
  assert.equal(state.status, 200);
  assert.equal(state.body.server.name, 'SoooDreamy');
  assert.ok(state.body.server.storage.couples >= 1);

  const couple = state.body.couples.find((c) => c.id === pair.coupleId);
  assert.ok(couple, 'created couple shows up');
  assert.equal(couple.code, pair.code);
  assert.equal(couple.health, 'ok');
  assert.equal(couple.members.length, 2);
  assert.equal(couple.counts.messages, 1);
  assert.ok(couple.lastActiveAt, 'activity is tracked');
  const mia = couple.members.find((m) => m.id === pair.a.memberId);
  assert.deepEqual(mia.appVersions, ['SoooDreamy/47 CFNetwork/1490 Darwin/23']);
  assert.ok(mia.activeSessions >= 1);
});

test('state reports quarantined couples so the operator notices', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-admin-quarantine-'));
  const first = await makeApp(null, { dataDir });
  const pair = await setupCouple(first.baseUrl);
  await first.close();
  // Simulate losing every recovery generation, then corrupt the live segment:
  // without a valid segment, .bak, or WAL this couple is unrecoverable.
  await rm(path.join(dataDir, 'store.wal'), { force: true });
  await writeFile(
    path.join(dataDir, 'segments', `${encodeURIComponent(pair.coupleId)}.json`),
    '{"format":"segment-v2","sha256":"00', 'utf8');

  const ctx = await makeApp(t, { dataDir });
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const admin = await adminLogin(ctx);
  const state = await admin.get('/state');
  assert.equal(state.body.couples.find((c) => c.id === pair.coupleId), undefined);
  const quarantined = state.body.quarantined.find((q) => q.id === pair.coupleId);
  assert.ok(quarantined, 'quarantined couple is listed');
  assert.equal(quarantined.health, 'quarantined');
  assert.ok(quarantined.files.length >= 1);
  assert.ok(quarantined.files[0].reason);
});

test('invite-code reset invalidates the old code immediately', async (t) => {
  const ctx = await makeApp(t);
  const anon = client(ctx.baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Solo' } });
  const oldCode = created.body.couple.code;

  const admin = await adminLogin(ctx);
  const reset = await admin.post(`/couples/${created.body.coupleId}/invite-code/reset`);
  assert.equal(reset.status, 200);
  assert.match(reset.body.code, /^[A-Z2-9]{6}$/);
  assert.notEqual(reset.body.code, oldCode);

  const oldJoin = await anon.post('/api/couples/join', { json: { code: oldCode, name: 'Late' } });
  assert.equal(oldJoin.status, 404, 'old invite code is dead');
  const newJoin = await anon.post('/api/couples/join', { json: { code: reset.body.code, name: 'Late' } });
  assert.equal(newJoin.status, 200, 'new invite code works');
});

test('recovery-key reset invalidates the previous key and the new one rejoins', async (t) => {
  const ctx = await makeApp(t);
  const anon = client(ctx.baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Mia' } });
  const originalKey = created.body.recoveryKey;
  const code = created.body.couple.code;

  const admin = await adminLogin(ctx);
  const reset = await admin.post(
    `/couples/${created.body.coupleId}/members/${created.body.memberId}/recovery-key/reset`);
  assert.equal(reset.status, 200);
  assert.match(reset.body.recoveryKey, /^rec_[0-9a-f]{40}$/);

  const staleRejoin = await anon.post('/api/couples/rejoin', {
    json: { code, recoveryKey: originalKey },
  });
  assert.equal(staleRejoin.status, 403, 'pre-reset recovery key is invalid');
  const freshRejoin = await anon.post('/api/couples/rejoin', {
    json: { code, recoveryKey: reset.body.recoveryKey },
  });
  assert.equal(freshRejoin.status, 200);
  assert.equal(freshRejoin.body.rejoined, true);
});

test('replace-code reset lets a new device take over the slot (old sessions die)', async (t) => {
  const ctx = await makeApp(t);
  const pair = await setupCouple(ctx.baseUrl);
  const admin = await adminLogin(ctx);

  const first = await admin.post(
    `/couples/${pair.coupleId}/members/${pair.b.memberId}/replace-code/reset`);
  assert.equal(first.status, 200);
  const second = await admin.post(
    `/couples/${pair.coupleId}/members/${pair.b.memberId}/replace-code/reset`);
  assert.equal(second.status, 200);
  assert.match(second.body.replaceCode, /^[A-Z2-9]{8}$/);

  const anon = client(ctx.baseUrl);
  const staleUse = await anon.post('/api/couples/rejoin', {
    json: { code: pair.code, replaceCode: first.body.replaceCode },
  });
  assert.equal(staleUse.status, 403, 'the older admin code was invalidated by the reset');

  const takeOver = await anon.post('/api/couples/rejoin', {
    json: { code: pair.code, replaceCode: second.body.replaceCode, name: 'Ben neu' },
  });
  assert.equal(takeOver.status, 200);
  assert.equal(takeOver.body.method, 'replaceCode');
  // The replaced slot got a fresh start: Ben's old bearer is gone.
  assert.equal((await pair.b.api.get('/api/couple')).status, 401);
});

test('admin session revoke works immediately; revoke-all clears the whole slot', async (t) => {
  const ctx = await makeApp(t);
  const pair = await setupCouple(ctx.baseUrl);
  // Ben re-attaches once more → second live session on the same slot.
  const extra = await client(ctx.baseUrl).post('/api/couples/rejoin', { json: { token: pair.b.token } });
  assert.equal(extra.status, 200);

  const admin = await adminLogin(ctx);
  const sessions = await admin.get(`/couples/${pair.coupleId}/sessions`);
  assert.equal(sessions.status, 200);
  const bensSessions = sessions.body.sessions.filter((s) => s.memberId === pair.b.memberId && s.live);
  assert.ok(bensSessions.length >= 2);
  assert.ok(sessions.body.sessions.every((s) => s.deviceName && s.lastUsedAt !== undefined));

  const target = bensSessions.find((s) => s.sessionId === extra.body.sessionId);
  const revoke = await admin.post(`/sessions/${target.sessionId}/revoke`);
  assert.equal(revoke.status, 200);
  const revokedUse = await client(ctx.baseUrl, extra.body.token).get('/api/couple');
  assert.equal(revokedUse.status, 401, 'revoked session is dead immediately');
  assert.equal((await pair.b.api.get('/api/couple')).status, 200, 'other session unaffected');

  const revokeAll = await admin.post(
    `/couples/${pair.coupleId}/members/${pair.b.memberId}/sessions/revoke-all`);
  assert.equal(revokeAll.status, 200);
  assert.ok(revokeAll.body.revoked >= 1);
  assert.equal((await pair.b.api.get('/api/couple')).status, 401);
  assert.equal((await pair.a.api.get('/api/couple')).status, 200, 'partner slot untouched');
});

test('login QR is a fixed-slot, expiring, atomic one-time nonce and never a bearer', async (t) => {
  const ctx = await makeApp(t);
  const pair = await setupCouple(ctx.baseUrl);
  const admin = await adminLogin(ctx);

  const qr = await admin.post(
    `/couples/${pair.coupleId}/members/${pair.a.memberId}/rejoin-qr`,
    { server: 'https://dreamy.example.com:4321/' });
  assert.equal(qr.status, 200);
  assert.ok(qr.body.svg.startsWith('<svg'), 'QR is rendered as SVG');
  assert.match(qr.body.deepLink,
    /^sooodreamy:\/\/rejoin\?server=https%3A%2F%2Fdreamy\.example\.com%3A4321&token=qr_[0-9a-f]+$/,
    'deep link format is sooodreamy://rejoin?server=<url-encoded>&token=<token>');
  assert.ok(Date.parse(qr.body.expiresAt) > Date.now(), 'short-lived QR token');

  // A nonce is not a device session and cannot authenticate as a bearer.
  const sessions = await admin.get(`/couples/${pair.coupleId}/sessions`);
  assert.ok(!sessions.body.sessions.some((s) => s.sessionId === qr.body.nonceId));

  const token = new URLSearchParams(qr.body.deepLink.split('?')[1]).get('token');
  assert.equal((await client(ctx.baseUrl, token).get('/api/couple')).status, 401);

  // Two simultaneous scans consume the proof atomically: exactly one wins.
  const attempts = await Promise.all([
    client(ctx.baseUrl).post('/api/couples/rejoin', {
      json: { token, deviceId: 'scan-a', deviceName: 'Scanned iPhone A' },
    }),
    client(ctx.baseUrl).post('/api/couples/rejoin', {
      json: { token, deviceId: 'scan-b', deviceName: 'Scanned iPhone B' },
    }),
  ]);
  assert.deepEqual(attempts.map((attempt) => attempt.status).sort(), [200, 409]);
  const rejoin = attempts.find((attempt) => attempt.status === 200);
  assert.equal(rejoin.body.rejoined, true);
  assert.equal(rejoin.body.method, 'adminQr');
  assert.equal(rejoin.body.memberId, pair.a.memberId, 'QR re-attaches the RIGHT slot');
  const fresh = await client(ctx.baseUrl, rejoin.body.token).get('/api/couple');
  assert.equal(fresh.status, 200);

  // An unconsumed but expired nonce is not accepted as a rejoin proof.
  const expiring = await admin.post(
    `/couples/${pair.coupleId}/members/${pair.a.memberId}/rejoin-qr`,
    { server: 'https://dreamy.example.com:4321/' });
  const expiredToken = new URLSearchParams(expiring.body.deepLink.split('?')[1]).get('token');
  const expiredDigest = crypto.createHash('sha256').update(expiredToken).digest('hex');
  ctx.app.store.data.qrNonces[expiredDigest].expiresAt = '2000-01-01T00:00:00.000Z';
  ctx.app.store.markDirty();
  const expired = await client(ctx.baseUrl).post('/api/couples/rejoin', {
    json: { token: expiredToken, deviceId: 'expired-scan' },
  });
  assert.equal(expired.status, 403);
  assert.equal(expired.body.error, 'qr_expired');

  const badServer = await admin.post(
    `/couples/${pair.coupleId}/members/${pair.a.memberId}/rejoin-qr`,
    { server: 'javascript:alert(1)' });
  assert.equal(badServer.status, 400, 'only http(s) base URLs go into the QR');
});

test('backup-now creates a verified backup and the panel lists it', async (t) => {
  const ctx = await makeApp(t);
  await setupCouple(ctx.baseUrl);
  const admin = await adminLogin(ctx);
  const created = await admin.post('/backups');
  assert.equal(created.status, 200);
  assert.match(created.body.backup.id, /-admin$/);
  assert.ok(created.body.backup.files >= 1);

  const listed = await admin.get('/backups');
  assert.equal(listed.status, 200);
  assert.ok(listed.body.backups.some((b) => b.id === created.body.backup.id));
});

test('log tail and append-only audit trail capture admin activity', async (t) => {
  const ctx = await makeApp(t);
  const pair = await setupCouple(ctx.baseUrl);
  const admin = await adminLogin(ctx);
  await admin.post(`/couples/${pair.coupleId}/invite-code/reset`);
  await admin.post(`/couples/${pair.coupleId}/members/${pair.a.memberId}/recovery-key/reset`);

  const logs = await admin.get('/logs');
  assert.equal(logs.status, 200);
  assert.ok(Array.isArray(logs.body.lines));
  assert.ok(logs.body.lines.length <= 200);
  assert.ok(logs.body.lines.some((entry) => /admin: invite code/.test(entry.line)));

  const auditApi = await admin.get('/audit');
  const actions = auditApi.body.entries.map((entry) => entry.action);
  for (const expected of ['login', 'invite_code_reset', 'recovery_key_reset']) {
    assert.ok(actions.includes(expected), `audit contains ${expected}`);
  }

  // The trail is a plain append-only JSONL file in the data dir.
  await ctx.app.admin.close();
  const raw = await readFile(path.join(ctx.dataDir, 'admin-audit.log'), 'utf8');
  const lines = raw.trim().split('\n').map((line) => JSON.parse(line));
  assert.ok(lines.length >= 3);
  assert.ok(lines.every((entry) => entry.at && entry.action && entry.ip));
  assert.equal(lines.some((entry) => /rec_[0-9a-f]/.test(JSON.stringify(entry))), false,
    'no secret ever lands in the audit file');
});

test('audit logs rotate by size and retain only the configured generations', async (t) => {
  const ctx = await makeApp(t, { auditMaxBytes: 1, auditRetentionFiles: 2 });
  let admin;
  for (let index = 0; index < 5; index += 1) {
    admin = await adminLogin(ctx);
    if (index < 4) await admin.post('/logout');
  }
  await admin.get('/audit'); // drains the serialized audit write chain
  const files = await readdir(ctx.dataDir);
  const rotated = files.filter((name) => /^admin-audit-.+\.log$/u.test(name));
  assert.equal(rotated.length, 2);
  assert.ok(files.includes('admin-audit.log'));
});
