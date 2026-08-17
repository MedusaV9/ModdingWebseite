// W14/NETSET — optionales Join-Secret (ENV GOOBY_JOIN_SECRET, cfg.joinSecret):
// ohne Config bleibt ALLES wie bisher (Kompatibilität, auch mit überflüssigem
// secret-Feld); mit Config werden fehlende/falsche Secrets höflich abgelehnt
// (SECRET_REQUIRED/SECRET_WRONG, Close 4008, KEIN Spieler-Eintrag) und das
// richtige Secret läuft normal durch HELLO → WELCOME.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient } from './helpers.js';
import { checkJoinSecret } from '../src/auth.js';

test('ohne joinSecret-Config: HELLO ohne UND mit secret-Feld wie bisher', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());

  // Bestandsverhalten: nacktes HELLO → WELCOME.
  const plain = await WsClient.connect(server.wsUrl);
  const welcome = await plain.hello(newIdentity('Klassik'));
  assert.equal(welcome.t, 'WELCOME');
  plain.close();

  // Kompatibilität: ein Client, der (vorkonfiguriert) trotzdem ein secret
  // mitschickt, wird NICHT abgelehnt — das Feld wird schlicht ignoriert.
  const eager = await WsClient.connect(server.wsUrl);
  const welcome2 = await eager.hello(newIdentity('Vorkonfiguriert'), { secret: 'egal' });
  assert.equal(welcome2.t, 'WELCOME');
  eager.close();
});

test('mit joinSecret: fehlend → SECRET_REQUIRED, falsch → SECRET_WRONG (kein Spieler-Eintrag)', async (t) => {
  const server = await startServer({ env: { GOOBY_JOIN_SECRET: 'streng-geheim' } });
  t.after(() => server.stop());

  const ohne = await WsClient.connect(server.wsUrl);
  const idOhne = newIdentity('Ohne');
  const err = await ohne.hello(idOhne);
  assert.equal(err.t, 'ERROR');
  assert.equal(err.d.code, 'SECRET_REQUIRED');
  await ohne.waitClose();
  assert.equal(server.ctx.players[idOhne.deviceId], undefined, 'abgelehnt = kein TOFU-Eintrag');

  const falsch = await WsClient.connect(server.wsUrl);
  const idFalsch = newIdentity('Falsch');
  const err2 = await falsch.hello(idFalsch, { secret: 'streng-geheim-aber-anders' });
  assert.equal(err2.t, 'ERROR');
  assert.equal(err2.d.code, 'SECRET_WRONG');
  await falsch.waitClose();
  assert.equal(server.ctx.players[idFalsch.deviceId], undefined);
});

test('mit joinSecret: richtiges Secret → WELCOME, Reconnect behält Identität', async (t) => {
  const server = await startServer({ env: { GOOBY_JOIN_SECRET: 'streng-geheim' } });
  t.after(() => server.stop());
  const id = newIdentity('Richtig');

  const c1 = await WsClient.connect(server.wsUrl);
  const welcome = await c1.hello(id, { secret: 'streng-geheim' });
  assert.equal(welcome.t, 'WELCOME');
  assert.match(welcome.d.friendCode, /^GOOBY-[A-HJ-NP-Z2-9]{4}$/);
  c1.close();
  await c1.waitClose();

  const c2 = await WsClient.connect(server.wsUrl);
  const welcome2 = await c2.hello(id, { secret: 'streng-geheim' });
  assert.equal(welcome2.d.friendCode, welcome.d.friendCode, 'gleicher Account');
  c2.close();
});

test('checkJoinSecret pur: No-op ohne Config, Codes mit Config', () => {
  assert.equal(checkJoinSecret({ joinSecret: null }, undefined), null);
  assert.equal(checkJoinSecret({ joinSecret: null }, 'egal'), null);
  assert.equal(checkJoinSecret({ joinSecret: 's3cret' }, undefined), 'SECRET_REQUIRED');
  assert.equal(checkJoinSecret({ joinSecret: 's3cret' }, ''), 'SECRET_REQUIRED');
  assert.equal(checkJoinSecret({ joinSecret: 's3cret' }, 42), 'SECRET_REQUIRED');
  assert.equal(checkJoinSecret({ joinSecret: 's3cret' }, 'falsch'), 'SECRET_WRONG');
  assert.equal(checkJoinSecret({ joinSecret: 's3cret' }, 's3cret'), null);
});
