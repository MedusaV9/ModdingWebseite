// Ban-Verwaltung (W13-C, Befund P3): Panel-Ban mit Pflicht-Begründung trennt die
// laufende Session, jedes neue HELLO wird höflich mit BANNED abgelehnt (Client
// zeigt seinen Offline-Chip — der Reconnect-Backoff läuft normal weiter), REST
// antwortet 403 BANNED (nur bei KORREKTEM Secret — kein Enumeration-Orakel),
// Audit-Log hält wer/wann/warum fest, Unban öffnet das Gate wieder, und der
// Ban überlebt einen Server-Neustart (flushNow).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient, bearer } from './helpers.js';

const PW = 'super-geheim-123';

async function login(server) {
  const res = await fetch(`${server.url}/panel/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `password=${encodeURIComponent(PW)}`,
    redirect: 'manual',
  });
  return res.headers.get('set-cookie')?.split(';')[0];
}

function postForm(server, path, cookie, body) {
  return fetch(`${server.url}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', cookie },
    body: Object.entries(body)
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
      .join('&'),
  });
}

test('Ban-Gate: Pflicht-Begründung, Session-Trennung, HELLO → BANNED, REST 403, Audit, Neustart', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  const dataDir = server.dataDir;
  const id = newIdentity('Anna');
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(id);
  const cookie = await login(server);

  // Ohne Begründung KEIN Ban (Pflichtfeld, Audit "warum").
  const noReason = await postForm(server, '/panel/api/ban', cookie, {
    deviceId: id.deviceId,
    reason: '   ',
  });
  assert.equal(noReason.status, 400);
  assert.match(await noReason.text(), /REASON_REQUIRED/);
  assert.equal(server.ctx.players[id.deviceId].banned, false);

  // Ban mit Begründung → bestehende Session wird höflich getrennt.
  const banned = await postForm(server, '/panel/api/ban', cookie, {
    deviceId: id.deviceId,
    reason: 'Beleidigungen im Chat',
  });
  assert.equal(banned.status, 200);
  const goingDown = await c.next('GOING_DOWN');
  assert.equal(goingDown.d.reason, 'BANNED');
  await c.waitClose();

  // Reconnect: HELLO wird höflich abgelehnt (ERROR BANNED + Close) —
  // client-kompatibel: der NetClient zeigt Offline-Chip und backofft weiter.
  const c2 = await WsClient.connect(server.wsUrl);
  const rejected = await c2.hello(id);
  assert.equal(rejected.t, 'ERROR');
  assert.equal(rejected.d.code, 'BANNED');
  await c2.waitClose();

  // REST: korrektes Secret eines Gebannten → explizit 403 BANNED.
  const rest = await fetch(`${server.url}/api/house/${server.ctx.players[id.deviceId].friendCode}`, {
    headers: { authorization: bearer(id) },
  });
  assert.equal(rest.status, 403);
  assert.equal((await rest.json()).code, 'BANNED');
  // FALSCHES Secret bleibt beim einheitlichen 401 (kein "gebannt"-Orakel).
  const wrong = await fetch(`${server.url}/api/house/${server.ctx.players[id.deviceId].friendCode}`, {
    headers: { authorization: `Bearer ${id.deviceId}:${'0'.repeat(64)}` },
  });
  assert.equal(wrong.status, 401);

  // Spieler-Seite zeigt Status + Audit mit Begründung.
  const page = await (
    await fetch(`${server.url}/panel/players`, { headers: { cookie } })
  ).text();
  assert.match(page, /GEBANNT/);
  assert.match(page, /Beleidigungen im Chat/);
  assert.match(page, /Moderations-Audit/);

  // Ban überlebt den Neustart (flushNow, kein Write-behind-Fenster).
  await server.stop({ keepData: true });
  const s2 = await startServer({ dataDir, env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => s2.stop());
  const c3 = await WsClient.connect(s2.wsUrl);
  const stillBanned = await c3.hello(id);
  assert.equal(stillBanned.d.code, 'BANNED');
  await c3.waitClose();

  // Unban (ebenfalls mit Pflicht-Begründung) → HELLO läuft wieder.
  const cookie2 = await login(s2);
  const unbanned = await postForm(s2, '/panel/api/unban', cookie2, {
    deviceId: id.deviceId,
    reason: 'Entschuldigung angenommen',
  });
  assert.equal(unbanned.status, 200);
  const c4 = await WsClient.connect(s2.wsUrl);
  const welcome = await c4.hello(id);
  assert.equal(welcome.t, 'WELCOME');
  c4.close();

  // Audit: Ban UND Unban mit wer/wann/warum.
  const audit = s2.ctx.store.collection('bans', { audit: [] }).audit;
  assert.equal(audit.length, 2);
  assert.equal(audit[0].action, 'ban');
  assert.equal(audit[0].reason, 'Beleidigungen im Chat');
  assert.equal(audit[0].by, 'panel');
  assert.ok(Number.isFinite(audit[0].at));
  assert.equal(audit[1].action, 'unban');
  assert.equal(audit[1].reason, 'Entschuldigung angenommen');
});

test('Ban-API: unbekannte deviceId und Doppel-Ban werden sauber abgelehnt', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => server.stop());
  const id = newIdentity('Ben');
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(id);
  t.after(() => c.close());
  const cookie = await login(server);

  const missing = await postForm(server, '/panel/api/ban', cookie, {
    deviceId: 'gd-gibtsnicht00000000',
    reason: 'egal',
  });
  assert.equal(missing.status, 400);
  assert.match(await missing.text(), /NOT_FOUND/);

  assert.equal(
    (await postForm(server, '/panel/api/ban', cookie, { deviceId: id.deviceId, reason: 'Test' }))
      .status,
    200
  );
  const twice = await postForm(server, '/panel/api/ban', cookie, {
    deviceId: id.deviceId,
    reason: 'nochmal',
  });
  assert.equal(twice.status, 400);
  assert.match(await twice.text(), /ALREADY_BANNED/);

  // Unban eines Nicht-Gebannten → NOT_BANNED.
  const id2 = newIdentity('Carla');
  const c2 = await WsClient.connect(server.wsUrl);
  await c2.hello(id2);
  t.after(() => c2.close());
  const notBanned = await postForm(server, '/panel/api/unban', cookie, {
    deviceId: id2.deviceId,
    reason: 'egal',
  });
  assert.equal(notBanned.status, 400);
  assert.match(await notBanned.text(), /NOT_BANNED/);
});

test('Ban-Panel-API ist nur mit Session nutzbar (sonst Redirect, kein Ban)', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => server.stop());
  const id = newIdentity('Anna');
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(id);
  t.after(() => c.close());
  const res = await fetch(`${server.url}/panel/api/ban`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `deviceId=${encodeURIComponent(id.deviceId)}&reason=hack`,
    redirect: 'manual',
  });
  assert.equal(res.status, 303);
  assert.equal(server.ctx.players[id.deviceId].banned, false);
});
