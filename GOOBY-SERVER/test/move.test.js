// Account-Umzugs-Code (Doc C §7, W13-C): Panel generiert einen einmaligen
// 8-Zeichen-Code (24 h, zeitinjiziert); das NEUE Gerät löst ihn per WS
// MOVE_REDEEM ein und übernimmt die Server-Identität ATOMAR (TOFU-Key-Rotation:
// alter Schlüssel sofort tot, FriendCode/Freunde/Pal-Historie hängen am neuen
// Gerät, altes Gerät bekommt GOING_DOWN MOVED). Einmaligkeit, Ablauf,
// Supersede (nur jüngster Code zählt) und Crash-Atomarität werden geprüft.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient, twoFriends } from './helpers.js';

const PW = 'super-geheim-123';
const CODE_IN_FLASH = /Umzugs-Code für [^:]+: <code>([A-HJ-NP-Z2-9]{8})<\/code>/;

async function login(server) {
  const res = await fetch(`${server.url}/panel/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `password=${encodeURIComponent(PW)}`,
    redirect: 'manual',
  });
  return res.headers.get('set-cookie')?.split(';')[0];
}

async function createCodeViaPanel(server, cookie, deviceId) {
  const res = await fetch(`${server.url}/panel/api/movecode`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', cookie },
    body: `deviceId=${encodeURIComponent(deviceId)}`,
  });
  assert.equal(res.status, 200);
  const match = (await res.text()).match(CODE_IN_FLASH);
  assert.ok(match, 'Flash enthält den Umzugs-Code');
  return match[1];
}

function fakeClock() {
  return { t: Date.now(), now() { return this.t; } };
}

test('Umzug: Identitäts-Übernahme atomar — alter Schlüssel tot, Freunde + Pal-Historie ziehen mit', async (t) => {
  const clock = fakeClock();
  const { server, a, b, idA, codeA, codeB } = await twoFriends(t, {
    env: { GOOBY_ADMIN_PASSWORD: PW },
    clock,
  });

  // Pal-Historie anlegen, die nach dem Umzug am Account hängen muss.
  const pal = await a.request('PAL_SEND', { to: codeB, amount: 50 });
  assert.equal(pal.d.ok, true);

  const cookie = await login(server);
  const code = await createCodeViaPanel(server, cookie, idA.deviceId);

  // NEUES Gerät: eigener Guest-Account, dann Code einlösen.
  const idNew = newIdentity('AnnaNeu');
  const neu = await WsClient.connect(server.wsUrl);
  await neu.hello(idNew);
  const result = await neu.request('MOVE_REDEEM', { code });
  assert.equal(result.t, 'MOVE_RESULT');
  assert.equal(result.d.ok, true);
  const identity = result.d.identity;
  assert.equal(identity.deviceId, idA.deviceId, 'übernommene deviceId = Alt-Account');
  assert.equal(identity.friendCode, codeA, 'FriendCode zieht mit');
  assert.notEqual(identity.deviceSecret, idA.deviceSecret, 'Secret ist ROTIERT');

  // Altes Gerät wird höflich abgemeldet; die Einlöse-Verbindung ebenso
  // (der Client verbindet sich mit der übernommenen Identität neu).
  const moved = await a.next('GOING_DOWN');
  assert.equal(moved.d.reason, 'MOVED');
  await a.waitClose();
  await neu.waitClose();

  // Alter Schlüssel: HELLO → AUTH_FAIL (TOFU-Rotation).
  const alt = await WsClient.connect(server.wsUrl);
  const rejected = await alt.hello(idA);
  assert.equal(rejected.t, 'ERROR');
  assert.equal(rejected.d.code, 'AUTH_FAIL');
  await alt.waitClose();

  // Neue Identität: WELCOME mit dem alten FriendCode, Freunde + Pal-Historie da.
  const c2 = await WsClient.connect(server.wsUrl);
  t.after(() => c2.close());
  const welcome = await c2.hello({
    deviceId: identity.deviceId,
    deviceSecret: identity.deviceSecret,
    name: 'Anna',
    goobyName: 'Flausch',
  });
  assert.equal(welcome.t, 'WELCOME');
  assert.equal(welcome.d.friendCode, codeA);
  const friends = await c2.request('FRIENDS_LIST');
  assert.ok(
    friends.d.friends.some((f) => f.friendCode === codeB),
    'Freundesliste zieht mit um'
  );
  const history = await c2.request('PAL_HISTORY');
  assert.ok(
    history.d.entries.some((e) => e.dir === 'out' && e.peer === codeB && e.amount === 50),
    'Pal-Historie zieht mit um'
  );

  // Wegwerf-Guest des neuen Geräts ist aufgeräumt; Ben blieb unangetastet.
  assert.equal(server.ctx.players[idNew.deviceId], undefined);
  assert.equal(server.ctx.byCode.get(codeB) !== undefined, true);
  b.close();
});

test('Umzugs-Code ist EINMALIG: zweite Einlösung → INVALID_CODE', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => server.stop());
  const idA = newIdentity('Anna');
  const a = await WsClient.connect(server.wsUrl);
  await a.hello(idA);
  const cookie = await login(server);
  const code = await createCodeViaPanel(server, cookie, idA.deviceId);

  const erst = await WsClient.connect(server.wsUrl);
  await erst.hello(newIdentity('Gerät1'));
  assert.equal((await erst.request('MOVE_REDEEM', { code })).d.ok, true);
  await erst.waitClose();

  const zweit = await WsClient.connect(server.wsUrl);
  t.after(() => zweit.close());
  await zweit.hello(newIdentity('Gerät2'));
  const again = await zweit.request('MOVE_REDEEM', { code });
  assert.equal(again.d.ok, false);
  assert.equal(again.d.code, 'INVALID_CODE');
});

test('Umzugs-Code läuft nach 24 h ab (zeitinjiziert) → EXPIRED', async (t) => {
  const clock = fakeClock();
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW }, clock });
  t.after(() => server.stop());
  const idA = newIdentity('Anna');
  const a = await WsClient.connect(server.wsUrl);
  await a.hello(idA);
  a.close();
  const cookie = await login(server);
  const code = await createCodeViaPanel(server, cookie, idA.deviceId);

  clock.t += 24 * 3600_000 + 60_000; // 24 h + 1 min

  const neu = await WsClient.connect(server.wsUrl);
  t.after(() => neu.close());
  await neu.hello(newIdentity('Spät'));
  const result = await neu.request('MOVE_REDEEM', { code });
  assert.equal(result.d.ok, false);
  assert.equal(result.d.code, 'EXPIRED');
});

test('Pro Account zählt nur der JÜNGSTE Code (alte werden supersedet); Unsinn → INVALID_CODE', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => server.stop());
  const idA = newIdentity('Anna');
  const a = await WsClient.connect(server.wsUrl);
  await a.hello(idA);
  const cookie = await login(server);
  const code1 = await createCodeViaPanel(server, cookie, idA.deviceId);
  const code2 = await createCodeViaPanel(server, cookie, idA.deviceId);
  assert.notEqual(code1, code2);

  const neu = await WsClient.connect(server.wsUrl);
  await neu.hello(newIdentity('Neu'));
  const superseded = await neu.request('MOVE_REDEEM', { code: code1 });
  assert.equal(superseded.d.ok, false);
  assert.equal(superseded.d.code, 'INVALID_CODE');
  const garbage = await neu.request('MOVE_REDEEM', { code: 'zu-kurz' });
  assert.equal(garbage.d.code, 'INVALID_CODE');
  const ok = await neu.request('MOVE_REDEEM', { code: code2 });
  assert.equal(ok.d.ok, true);
  await neu.waitClose();
});

test('Umzug-Crash: Rotation + Entwertung sind VOR der Antwort persistiert (flushNow)', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  const dataDir = server.dataDir;
  const idA = newIdentity('Anna');
  const a = await WsClient.connect(server.wsUrl);
  await a.hello(idA);
  const cookie = await login(server);
  const code = await createCodeViaPanel(server, cookie, idA.deviceId);

  const neu = await WsClient.connect(server.wsUrl);
  await neu.hello(newIdentity('Neu'));
  const result = await neu.request('MOVE_REDEEM', { code });
  assert.equal(result.d.ok, true);
  const identity = result.d.identity;
  // Absturz DIREKT nach der Antwort — ohne Write-behind-Flush.
  await server.crash();

  const s2 = await startServer({ dataDir, env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => s2.stop());
  // Alter Schlüssel bleibt tot, neuer funktioniert, Code bleibt entwertet.
  const alt = await WsClient.connect(s2.wsUrl);
  assert.equal((await alt.hello(idA)).d.code, 'AUTH_FAIL');
  await alt.waitClose();
  const c2 = await WsClient.connect(s2.wsUrl);
  const welcome = await c2.hello({
    deviceId: identity.deviceId,
    deviceSecret: identity.deviceSecret,
    name: 'Anna',
  });
  assert.equal(welcome.t, 'WELCOME');
  assert.equal(welcome.d.friendCode, identity.friendCode);
  c2.close();
  const nochmal = await WsClient.connect(s2.wsUrl);
  t.after(() => nochmal.close());
  await nochmal.hello(newIdentity('Dieb'));
  const reuse = await nochmal.request('MOVE_REDEEM', { code });
  assert.equal(reuse.d.code, 'INVALID_CODE');
});

test('Gebannte Accounts sind nicht umziehbar (kein Ban-Escape per Umzugs-Code)', async (t) => {
  const server = await startServer({ env: { GOOBY_ADMIN_PASSWORD: PW } });
  t.after(() => server.stop());
  const idA = newIdentity('Anna');
  const a = await WsClient.connect(server.wsUrl);
  await a.hello(idA);
  const cookie = await login(server);
  const code = await createCodeViaPanel(server, cookie, idA.deviceId);
  // Danach bannen (Panel-API) — Code war zu dem Zeitpunkt schon erzeugt.
  await fetch(`${server.url}/panel/api/ban`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', cookie },
    body: `deviceId=${encodeURIComponent(idA.deviceId)}&reason=${encodeURIComponent('Cheating')}`,
  });
  const neu = await WsClient.connect(server.wsUrl);
  t.after(() => neu.close());
  await neu.hello(newIdentity('Neu'));
  const result = await neu.request('MOVE_REDEEM', { code });
  assert.equal(result.d.ok, false);
  assert.equal(result.d.code, 'INVALID_CODE');
});
