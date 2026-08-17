// GoobyPal: server-validierter Coin-Transfer, 250/Tag/Absender (dayKey in GOOBY_TZ),
// Offline-Gutschrift via Pull-Queue, Ledger-Append.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { startServer, newIdentity, WsClient, twoFriends } from './helpers.js';

test('PAL_SEND: Erfolg, Push an Empfänger, Ledger-Zeile', async (t) => {
  const { server, a, b, codeB } = await twoFriends(t);
  const res = await a.request('PAL_SEND', { to: codeB, amount: 50 });
  assert.equal(res.t, 'PAL_RESULT');
  assert.deepEqual(
    { ok: res.d.ok, sentToday: res.d.sentToday, dailyLimit: res.d.dailyLimit },
    { ok: true, sentToday: 50, dailyLimit: 250 }
  );
  const received = await b.next('PAL_RECEIVED');
  assert.equal(received.d.amount, 50);
  // Ledger (append-only, auditierbar).
  const ledgerDir = path.join(server.dataDir, 'ledger');
  const files = fs.readdirSync(ledgerDir);
  assert.equal(files.length, 1);
  const line = JSON.parse(fs.readFileSync(path.join(ledgerDir, files[0]), 'utf8').trim());
  assert.equal(line.amount, 50);
  assert.equal(line.to, codeB);
  assert.match(line.dayKey, /^\d{4}-\d{2}-\d{2}$/);
});

test('PAL_SEND-Fehlfälle: NOT_FRIENDS, BAD_AMOUNT, NOT_FOUND', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const a = await WsClient.connect(server.wsUrl);
  await a.hello(newIdentity('Anna'));
  const b = await WsClient.connect(server.wsUrl);
  const wb = await b.hello(newIdentity('Ben'));
  t.after(() => [a, b].forEach((c) => c.close()));
  const codeB = wb.d.friendCode;

  assert.equal((await a.request('PAL_SEND', { to: codeB, amount: 10 })).d.code, 'NOT_FRIENDS');
  assert.equal((await a.request('PAL_SEND', { to: 'GOOBY-XXXX', amount: 10 })).d.code, 'NOT_FOUND');
  // Freundschaft herstellen für BAD_AMOUNT-Checks.
  await a.request('FRIEND_REQUEST', { target: codeB });
  await b.next('FRIEND_REQUEST_INCOMING');
  const wa = await a.request('FRIENDS_LIST'); // codeA über eigene Liste nicht nötig — accept über requests
  void wa;
  const reqs = (await b.request('FRIENDS_LIST')).d.requests;
  await b.request('FRIEND_ACCEPT', { target: reqs[0].from });
  await a.next('FRIEND_ADDED');
  for (const amount of [0, -5, 1.5, 251, '50']) {
    const res = await a.request('PAL_SEND', { to: codeB, amount });
    assert.equal(res.d.code, 'BAD_AMOUNT', `amount=${amount}`);
  }
});

test('Tageslimit 250/Absender: 200+51 scheitert, 200+50 passt, neuer Tag (TZ) resettet', async (t) => {
  // Fake-Uhr: 2026-07-24 21:00 UTC = 23:00 Berlin — kurz vor Mitternacht in GOOBY_TZ.
  let now = Date.UTC(2026, 6, 24, 21, 0, 0);
  const clock = { now: () => now };
  const { server, a, b, codeB, idA } = await twoFriends(t, { clock });
  // b darf offline sein (Gutschrift → Pull-Queue); vermeidet Heartbeat-Wächter-Rennen
  // beim Zeitsprung der Fake-Uhr.
  b.close();
  await b.waitClose();
  assert.equal((await a.request('PAL_SEND', { to: codeB, amount: 200 })).d.ok, true);
  const over = await a.request('PAL_SEND', { to: codeB, amount: 51 });
  assert.equal(over.d.ok, false);
  assert.equal(over.d.code, 'DAILY_LIMIT');
  assert.equal(over.d.sentToday, 200);
  assert.equal((await a.request('PAL_SEND', { to: codeB, amount: 50 })).d.ok, true);
  assert.equal((await a.request('PAL_SEND', { to: codeB, amount: 1 })).d.code, 'DAILY_LIMIT');

  // 2 Stunden später: 23:00 UTC = 01:00 Berlin am 25.07. → dayKey-Wechsel, Limit frisch.
  now += 2 * 3600_000;
  // Neu verbinden (frische lastSeen-Zeitbasis für den Heartbeat-Wächter).
  a.close();
  await a.waitClose();
  const a2 = await WsClient.connect(server.wsUrl);
  await a2.hello(idA);
  t.after(() => a2.close());
  const fresh = await a2.request('PAL_SEND', { to: codeB, amount: 250 });
  assert.equal(fresh.d.ok, true);
  assert.equal(fresh.d.sentToday, 250);
});

test('Empfänger offline: Gutschrift wartet in WELCOME.palPending bis zum PAL_ACK', async (t) => {
  const { server, a, b, codeB, idB } = await twoFriends(t);
  b.close();
  await a.next('FRIEND_PRESENCE'); // offline-Push abwarten
  const res = await a.request('PAL_SEND', { to: codeB, amount: 77 });
  assert.equal(res.d.ok, true);
  const b2 = await WsClient.connect(server.wsUrl);
  const welcome = await b2.hello(idB);
  assert.equal(welcome.d.palPending.length, 1);
  assert.equal(welcome.d.palPending[0].amount, 77);
  assert.equal(typeof welcome.d.palPending[0].id, 'string');
  b2.close();
  await b2.waitClose();
  // OHNE Ack bleibt die Gutschrift liegen — ein verlorenes WELCOME
  // (Disconnect-Race) verliert nichts (E13 P1-2).
  const b3 = await WsClient.connect(server.wsUrl);
  const welcome3 = await b3.hello(idB);
  assert.equal(welcome3.d.palPending.length, 1);
  await b3.request('PAL_ACK', { id: welcome3.d.palPending[0].id });
  b3.close();
  await b3.waitClose();
  // Nach dem Ack ist die Queue leer.
  const b4 = await WsClient.connect(server.wsUrl);
  const welcome4 = await b4.hello(idB);
  assert.equal(welcome4.d.palPending.length, 0);
  b4.close();
});

test('Disconnect-Race: PAL_RECEIVED ohne Ack → Pull beim nächsten Connect', async (t) => {
  const { server, a, b, codeB, idB } = await twoFriends(t);
  const res = await a.request('PAL_SEND', { to: codeB, amount: 33 });
  assert.equal(res.d.ok, true);
  const received = await b.next('PAL_RECEIVED'); // live zugestellt…
  assert.equal(received.d.amount, 33);
  assert.equal(typeof received.d.id, 'string');
  b.close(); // …aber nie geackt (Client starb im Race)
  await b.waitClose();
  const b2 = await WsClient.connect(server.wsUrl);
  const welcome = await b2.hello(idB);
  assert.equal(welcome.d.palPending.length, 1);
  assert.equal(welcome.d.palPending[0].id, received.d.id);
  await b2.request('PAL_ACK', { id: received.d.id });
  b2.close();
  await b2.waitClose();
  const b3 = await WsClient.connect(server.wsUrl);
  assert.equal((await b3.hello(idB)).d.palPending.length, 0);
  b3.close();
});

test('PAL_HISTORY: letzte Transfers beider Richtungen', async (t) => {
  const { a, b, codeA, codeB } = await twoFriends(t);
  await a.request('PAL_SEND', { to: codeB, amount: 10 });
  await b.next('PAL_RECEIVED');
  await b.request('PAL_SEND', { to: codeA, amount: 20 });
  await a.next('PAL_RECEIVED');
  const hist = await a.request('PAL_HISTORY');
  assert.equal(hist.t, 'PAL_HISTORY_STATE');
  assert.deepEqual(
    hist.d.entries.map((e) => [e.dir, e.amount]),
    [['out', 10], ['in', 20]]
  );
  assert.equal(hist.d.sentToday, 10);
});
