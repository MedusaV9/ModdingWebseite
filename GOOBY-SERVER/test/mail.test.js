// Post/Mail (W13B, Doc C §3.7): Freunde-Pflicht + Fehlerfälle, Tages-Quota,
// Foto-REST (Magic-Bytes, Blob-Limit, Abruf nur Empfänger, Blob-Putzen),
// Postfach-Cap mit Verdrängung des ältesten GELESENEN, readAt-basiertes
// Prune (zeitinjiziert), Ack-Idempotenz, Geschenk-Roundtrip, clientId-Dedupe.
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient, twoFriends, bearer } from './helpers.js';
import { DAILY_LIMIT, MAILBOX_CAP } from '../src/mail.js';

const DAY_MS = 24 * 3600_000;

function sendMail(client, to, text, extra = {}) {
  return client.request('MAIL_SEND', { to, text, ...extra });
}

function postMail(server, id, body) {
  return fetch(`${server.url}/api/mail`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: bearer(id) },
    body: JSON.stringify(body),
  });
}

// Minimal gültiges PNG-Präfix + Füllbytes (Magic-Bytes-Check, kein Decoder).
function fakePng(size = 64) {
  const buf = Buffer.alloc(size, 7);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buf);
  return buf;
}

test('Mail: nur Freunde, Fehlerfälle, MAIL_NEW-Push + WELCOME.mailUnread', async (t) => {
  const { server, a, b, idB, codeA, codeB } = await twoFriends(t);

  // Happy Path: a → b, b (online) bekommt den Push mit Brief + unread.
  const res = await sendMail(a, codeB, 'Hallo Ben!');
  assert.equal(res.t, 'MAIL_RESULT');
  assert.equal(res.d.ok, true);
  assert.equal(res.d.sentToday, 1);
  assert.equal(res.d.dailyLimit, DAILY_LIMIT);
  const push = await b.next('MAIL_NEW');
  assert.equal(push.d.mail.from, codeA);
  assert.equal(push.d.mail.fromName, 'Anna');
  assert.equal(push.d.mail.text, 'Hallo Ben!');
  assert.equal(push.d.mail.read, false);
  assert.equal(push.d.unread, 1);

  // Fehlerfälle: Fremder, unbekannter Code, an sich selbst, leerer Umschlag,
  // Text-Limit (>500).
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(newIdentity('Cleo'));
  t.after(() => c.close());
  assert.equal((await sendMail(c, codeB, 'Hi')).d.code, 'NOT_FRIENDS');
  assert.equal((await sendMail(a, 'GOOBY-2222', 'Hi')).d.code, 'NOT_FOUND');
  assert.equal((await sendMail(a, codeA, 'Hi')).d.code, 'SELF');
  assert.equal((await sendMail(a, codeB, '   ')).d.code, 'BAD_MAIL');
  assert.equal((await sendMail(a, codeB, 'x'.repeat(501))).d.code, 'TEXT_TOO_LONG');

  // Reconnect des Empfängers: WELCOME meldet den ungelesenen Brief.
  const b2 = await WsClient.connect(server.wsUrl);
  t.after(() => b2.close());
  const welcome = await b2.hello(idB);
  assert.equal(welcome.d.mailUnread, 1);
});

test('Mail-Quota: 20 Briefe/Tag pro Sender, nächster Tag zählt frisch', async (t) => {
  let now = 1_700_000_000_000;
  const { a, codeB } = await twoFriends(t, { clock: { now: () => now } });

  for (let i = 0; i < DAILY_LIMIT; i++) {
    const res = await sendMail(a, codeB, `Brief ${i}`);
    assert.equal(res.d.ok, true, `Brief ${i} innerhalb der Quota`);
  }
  const over = await sendMail(a, codeB, 'einer zu viel');
  assert.equal(over.d.ok, false);
  assert.equal(over.d.code, 'DAILY_LIMIT');
  assert.equal(over.d.sentToday, DAILY_LIMIT);

  now += DAY_MS; // neuer dayKey → Quota frisch
  const fresh = await sendMail(a, codeB, 'guten Morgen');
  assert.equal(fresh.d.ok, true);
  assert.equal(fresh.d.sentToday, 1);
});

test('Foto-REST: Magic-Bytes, Blob-Limit, Abruf nur Empfänger, Löschen putzt Blob', async (t) => {
  const { server, b, idA, idB, codeB } = await twoFriends(t, {
    env: { GOOBY_MAX_PHOTO_KB: '1' },
  });

  // Kein Bild (Magic-Bytes) → 400; zu groß (dekodiert > 1 KB) → 413.
  const notImage = await postMail(server, idA, {
    to: codeB,
    text: '',
    photoB64: Buffer.from('kein bild').toString('base64'),
  });
  assert.equal(notImage.status, 400);
  assert.equal((await notImage.json()).code, 'BAD_PHOTO');
  const tooBig = await postMail(server, idA, {
    to: codeB,
    text: '',
    photoB64: fakePng(2048).toString('base64'),
  });
  assert.equal(tooBig.status, 413);
  assert.equal((await tooBig.json()).code, 'PHOTO_TOO_LARGE');

  // Gültiges kleines PNG → ok; Blob liegt unter data/mail/.
  const png = fakePng(256);
  const okRes = await postMail(server, idA, {
    to: codeB,
    text: 'Foto für dich!',
    photoB64: png.toString('base64'),
  });
  assert.equal(okRes.status, 200);
  assert.equal((await okRes.json()).ok, true);
  const push = await b.next('MAIL_NEW');
  const photoId = push.d.mail.photoId;
  assert.ok(photoId.startsWith('mailp-'));
  const blobFile = path.join(server.dataDir, 'mail', photoId);
  assert.ok(fs.existsSync(blobFile), 'Blob-Datei liegt unter data/mail/');

  // Abruf: Empfänger bekommt das Foto zurück, der Absender NICHT (Brief
  // liegt nicht in seinem Postfach), ohne Auth 401.
  const fetched = await fetch(`${server.url}/api/mail/blob/${photoId}`, {
    headers: { authorization: bearer(idB) },
  });
  const body = await fetched.json();
  assert.equal(body.ok, true);
  assert.deepEqual(Buffer.from(body.photoB64, 'base64'), png);
  const senderTry = await fetch(`${server.url}/api/mail/blob/${photoId}`, {
    headers: { authorization: bearer(idA) },
  });
  assert.equal(senderTry.status, 404);
  assert.equal((await fetch(`${server.url}/api/mail/blob/${photoId}`)).status, 401);

  // Löschen räumt den Blob mit weg.
  const del = await b.request('MAIL_DELETE', { id: push.d.mail.id });
  assert.equal(del.d.removed, true);
  assert.equal(fs.existsSync(blobFile), false, 'Blob nach Löschen weg');
  // Zweites Löschen ist idempotent harmlos.
  assert.equal((await b.request('MAIL_DELETE', { id: push.d.mail.id })).d.removed, false);
});

test('Postfach-Cap 50: ältester GELESENER fliegt, sonst MAILBOX_FULL', async (t) => {
  let now = 1_700_000_000_000;
  const { a, b, codeB } = await twoFriends(t, { clock: { now: () => now } });

  // 50 Briefe über 3 Tage (Quota 20/Tag) — alle ungelesen.
  const ids = [];
  for (let i = 0; i < MAILBOX_CAP; i++) {
    if (i > 0 && i % DAILY_LIMIT === 0) now += DAY_MS;
    now += 1000; // eindeutige at-Reihenfolge
    const res = await sendMail(a, codeB, `Brief ${i}`);
    assert.equal(res.d.ok, true, `Brief ${i} zugestellt`);
    ids.push(res.d.id);
  }
  now += DAY_MS;

  // Voll + nichts gelesen → fail-closed.
  const full = await sendMail(a, codeB, 'passt nicht mehr');
  assert.equal(full.d.code, 'MAILBOX_FULL');

  // b liest die beiden ÄLTESTEN Briefe → genau der älteste gelesene fliegt.
  await b.request('MAIL_ACK', { id: ids[1] });
  await b.request('MAIL_ACK', { id: ids[0] });
  const retry = await sendMail(a, codeB, 'jetzt passt es');
  assert.equal(retry.d.ok, true);
  const list = await b.request('MAIL_LIST', { limit: 50 });
  assert.equal(list.d.total, MAILBOX_CAP, 'Cap hält das Postfach bei 50');
  const listedIds = list.d.mails.map((m) => m.id);
  assert.ok(!listedIds.includes(ids[0]), 'ältester gelesener wurde verdrängt');
  assert.ok(listedIds.includes(ids[1]), 'jüngerer gelesener bleibt');
  assert.ok(listedIds.includes(retry.d.id), 'neuer Brief ist drin');
  // Sortierung: ungelesene zuerst.
  const firstReadIdx = list.d.mails.findIndex((m) => m.read);
  assert.equal(firstReadIdx, list.d.mails.length - 1, 'gelesene stehen hinten');
});

test('Prune: gelesene Briefe fliegen 30 Tage nach dem Lesen (Blob mit)', async (t) => {
  let now = 1_700_000_000_000;
  const { server, a, b, idA, codeB } = await twoFriends(t, {
    clock: { now: () => now },
    env: { GOOBY_MAX_PHOTO_KB: '1' },
  });

  await postMail(server, idA, { to: codeB, text: 'mit Foto', photoB64: fakePng().toString('base64') });
  const withPhoto = (await b.next('MAIL_NEW')).d.mail;
  await sendMail(a, codeB, 'bleibt ungelesen');
  const blobFile = path.join(server.dataDir, 'mail', withPhoto.photoId);
  assert.ok(fs.existsSync(blobFile));

  await b.request('MAIL_ACK', { id: withPhoto.id });
  now += 29 * DAY_MS;
  assert.equal((await b.request('MAIL_LIST', {})).d.total, 2, '29 Tage: noch alles da');
  now += 2 * DAY_MS;
  const pruned = await b.request('MAIL_LIST', {});
  assert.equal(pruned.d.total, 1, 'gelesener Brief nach >30 Tagen weg');
  assert.equal(pruned.d.mails[0].text, 'bleibt ungelesen', 'ungelesener bleibt liegen');
  assert.equal(fs.existsSync(blobFile), false, 'Foto-Blob wurde mitgeputzt');
});

test('Ack ist idempotent: readAt bleibt beim ersten Lese-Zeitpunkt', async (t) => {
  let now = 1_700_000_000_000;
  const { server, a, b, codeB } = await twoFriends(t, { clock: { now: () => now } });

  const sent = await sendMail(a, codeB, 'lies mich');
  const first = await b.request('MAIL_ACK', { id: sent.d.id });
  assert.equal(first.t, 'OK');
  assert.equal(first.d.unread, 0);
  const readAt = server.ctx.store.collection('mail').boxes[codeB][0].readAt;
  assert.equal(readAt, now);

  now += 10 * DAY_MS;
  const again = await b.request('MAIL_ACK', { id: sent.d.id });
  assert.equal(again.t, 'OK');
  assert.equal(again.d.unread, 0);
  assert.equal(
    server.ctx.store.collection('mail').boxes[codeB][0].readAt,
    readAt,
    'zweites Ack verschiebt die Prune-Uhr nicht'
  );
  assert.equal((await b.request('MAIL_ACK', { id: 'mail-gibtsnicht' })).d.code, 'NOT_FOUND');
});

test('Geschenk-Roundtrip: Senden → Liste → Claim einmalig', async (t) => {
  const { a, b, codeB } = await twoFriends(t);

  // Kaputte Geschenke werden abgelehnt.
  assert.equal(
    (await sendMail(a, codeB, 'kaputt', { item: { typ: 'gold', id: 'x' } })).d.code,
    'BAD_ITEM'
  );
  assert.equal(
    (await sendMail(a, codeB, 'kaputt', { item: { typ: 'food', id: 'nutella', menge: 0 } })).d
      .code,
    'BAD_ITEM'
  );

  const sent = await sendMail(a, codeB, 'Für dich!', {
    item: { typ: 'food', id: 'nutella', menge: 2 },
  });
  assert.equal(sent.d.ok, true);
  const list = await b.request('MAIL_LIST', {});
  const mail = list.d.mails.find((m) => m.id === sent.d.id);
  assert.deepEqual(mail.item, { typ: 'food', id: 'nutella', menge: 2 });
  assert.equal(mail.claimed, false);

  const claim = await b.request('MAIL_CLAIM', { id: sent.d.id });
  assert.equal(claim.t, 'OK');
  assert.deepEqual(claim.d.item, { typ: 'food', id: 'nutella', menge: 2 });
  const again = await b.request('MAIL_CLAIM', { id: sent.d.id });
  assert.equal(again.d.code, 'ALREADY_CLAIMED');
  // Brief ohne Geschenk → NOT_FOUND beim Claim.
  const plain = await sendMail(a, codeB, 'ohne Geschenk');
  assert.equal((await b.request('MAIL_CLAIM', { id: plain.d.id })).d.code, 'NOT_FOUND');
});

test('clientId-Dedupe: Outbox-Retry erzeugt keinen Doppel-Brief', async (t) => {
  const { a, b, codeB } = await twoFriends(t);
  const clientId = 'outbox-retry-0001';
  const first = await sendMail(a, codeB, 'nur einmal', { clientId });
  assert.equal(first.d.ok, true);
  const retry = await sendMail(a, codeB, 'nur einmal', { clientId });
  assert.equal(retry.d.ok, true);
  assert.equal(retry.d.dupe, true);
  assert.equal(retry.d.sentToday, 1, 'Duplikat zählt nicht gegen die Quota');
  const list = await b.request('MAIL_LIST', {});
  assert.equal(list.d.total, 1, 'genau EIN Brief im Postfach');
});
