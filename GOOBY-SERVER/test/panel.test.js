// Webpanel: FAIL-CLOSED ohne GOOBY_ADMIN_PASSWORD (503), Login-Flow mit Session-Cookie,
// Login-Rate-Limit, Seiten rendern, Codes/Events per Panel-API.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient, bearer } from './helpers.js';

const PW = 'super-geheim-123';

async function login(server, password = PW) {
  const res = await fetch(`${server.url}/panel/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `password=${encodeURIComponent(password)}`,
    redirect: 'manual',
  });
  const cookie = res.headers.get('set-cookie')?.split(';')[0];
  return { res, cookie };
}

test('FAIL-CLOSED: ohne GOOBY_ADMIN_PASSWORD ist ALLES unter /panel 503', async (t) => {
  const server = await startServer(); // kein Passwort gesetzt
  t.after(() => server.stop());
  for (const path of ['/panel', '/panel/', '/panel/login', '/panel/analytics', '/panel/api/codes']) {
    const res = await fetch(`${server.url}${path}`, { method: path.includes('api') ? 'POST' : 'GET' });
    assert.equal(res.status, 503, path);
  }
  // Spiel-Endpoints laufen trotzdem.
  assert.equal((await fetch(`${server.url}/health`)).status, 200);
});

test('Login: falsches Passwort 401, richtiges → Cookie → Seiten laden, Logout sperrt', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => server.stop());

  // Ohne Session → Redirect auf Login.
  const anon = await fetch(`${server.url}/panel/`, { redirect: 'manual' });
  assert.equal(anon.status, 303);

  const bad = await login(server, 'falsch');
  assert.equal(bad.res.status, 401);
  assert.equal(bad.cookie, undefined);

  const good = await login(server);
  assert.equal(good.res.status, 303);
  assert.match(good.cookie, /^gooby_panel=[0-9a-f]{64}$/);

  for (const [path, marker] of [
    ['/panel/', 'Dashboard'],
    ['/panel/analytics', 'Spielzeit pro Tag'],
    ['/panel/codes', 'Neuen Code anlegen'],
    ['/panel/events', 'Event auslösen'],
    ['/panel/friends', 'Freundschaften'],
    ['/panel/players', 'Spieler'],
  ]) {
    const res = await fetch(`${server.url}${path}`, { headers: { cookie: good.cookie } });
    assert.equal(res.status, 200, path);
    assert.match(await res.text(), new RegExp(marker), path);
  }

  // Logout invalidiert die Session.
  await fetch(`${server.url}/panel/logout`, { method: 'POST', headers: { cookie: good.cookie }, redirect: 'manual' });
  const after = await fetch(`${server.url}/panel/`, { headers: { cookie: good.cookie }, redirect: 'manual' });
  assert.equal(after.status, 303);
});

test('Login-Rate-Limit: nach 5 Versuchen 15 min Lockout (429)', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => server.stop());
  for (let i = 0; i < 5; i++) {
    assert.equal((await login(server, 'falsch')).res.status, 401);
  }
  // Auch das RICHTIGE Passwort wird jetzt abgelehnt.
  assert.equal((await login(server)).res.status, 429);
});

test('Panel-API: Code anlegen + deaktivieren, Event senden → Client-Wirkung', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => server.stop());
  const { cookie } = await login(server);
  const form = (body) =>
    Object.entries(body)
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
      .join('&');

  // Ohne Session: Panel-API nicht nutzbar.
  const noAuth = await fetch(`${server.url}/panel/api/codes`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: form({ code: 'HACK', reward: '{}' }),
    redirect: 'manual',
  });
  assert.equal(noAuth.status, 303);

  // Code anlegen → Redeem funktioniert für Client.
  const created = await fetch(`${server.url}/panel/api/codes`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', cookie },
    body: form({ code: 'PANEL26', reward: '{"coins":250}', maxUses: '10' }),
  });
  assert.equal(created.status, 200);
  assert.match(await created.text(), /PANEL26/);

  const id = newIdentity();
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(id);
  t.after(() => c.close());
  const redeemed = await (
    await fetch(`${server.url}/api/codes/redeem`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: bearer(id) },
      body: JSON.stringify({ code: 'PANEL26' }),
    })
  ).json();
  assert.equal(redeemed.ok, true);
  assert.deepEqual(redeemed.reward, { coins: 250 });

  // Deaktivieren → INACTIVE für alle weiteren Geräte.
  await fetch(`${server.url}/panel/api/codes/deactivate`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', cookie },
    body: form({ code: 'PANEL26' }),
  });
  const id2 = newIdentity('Zweite');
  const c2 = await WsClient.connect(server.wsUrl);
  await c2.hello(id2);
  t.after(() => c2.close());
  const inactive = await (
    await fetch(`${server.url}/api/codes/redeem`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: bearer(id2) },
      body: JSON.stringify({ code: 'PANEL26' }),
    })
  ).json();
  assert.equal(inactive.code, 'INACTIVE');

  // Event über Panel-API → Online-Client bekommt SERVER_EVENT-Push.
  const evt = await fetch(`${server.url}/panel/api/events`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', cookie },
    body: form({ type: 'WEATHER_RAIN', params: '{"durationMin":30}', target: 'all', ttlMin: '60' }),
  });
  assert.equal(evt.status, 200);
  const push = await c.next('SERVER_EVENT');
  assert.equal(push.d.type, 'WEATHER_RAIN');
  assert.equal(push.d.params.durationMin, 30);
});

test('XSS-Sanitize: Spielername mit HTML wird escaped gerendert', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => server.stop());
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(newIdentity('<script>alert(1)</script>'));
  t.after(() => c.close());
  const { cookie } = await login(server);
  const html = await (await fetch(`${server.url}/panel/players`, { headers: { cookie } })).text();
  assert.ok(!html.includes('<script>alert(1)</script>'), 'kein rohes Script-Tag');
  assert.ok(html.includes('&lt;script&gt;'), 'escaped sichtbar');
});
