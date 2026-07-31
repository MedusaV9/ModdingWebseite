// InstantGooby (W13C, Doc C §3.9): Fan-out an ALLE Freunde (zählt 1× gegen
// die gemeinsame Tages-Quota), Foto-Pflicht + Caption-Limit, Feed-Ringpuffer
// pro Empfänger (Cap 30, Blob-Putzen über refs), Like-Idempotenz („Möhre da
// lassen“ — 1 pro Freund pro Post, Push an den Autor) und die kind-Trennung
// vom Briefkasten (Posts landen NIE im Postfach, Briefe nie im Feed).
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient, twoFriends, bearer } from './helpers.js';
import { DAILY_LIMIT, CAPTION_MAX, FEED_CAP } from '../src/mail.js';

const DAY_MS = 24 * 3600_000;

function postInstant(server, id, body) {
  return fetch(`${server.url}/api/instant`, {
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

// Dritten Client verbinden und mit `host` befreunden (Fixture-Erweiterung).
async function addFriend(t, server, host, hostCode, name) {
  const id = newIdentity(name);
  const c = await WsClient.connect(server.wsUrl);
  t.after(() => c.close());
  const welcome = await c.hello(id);
  const code = welcome.d.friendCode;
  await c.request('FRIEND_REQUEST', { target: hostCode });
  await host.next('FRIEND_REQUEST_INCOMING');
  await host.request('FRIEND_ACCEPT', { target: code });
  await c.next('FRIEND_ADDED');
  await host.next('FRIEND_ADDED');
  return { client: c, id, code };
}

test('Instant: Fan-out an alle Freunde + kind-Trennung vom Briefkasten', async (t) => {
  const { server, a, b, idA, idB, codeA, codeB } = await twoFriends(t);
  const c = await addFriend(t, server, a, codeA, 'Cleo');

  // Ein Post → BEIDE Freunde bekommen den Push gleichzeitig.
  const res = await postInstant(server, idA, {
    caption: 'Möhrenernte!',
    photoB64: fakePng().toString('base64'),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.recipients, 2, 'Fan-out an beide Freunde');
  assert.equal(body.sentToday, 1, 'zählt 1× gegen die Quota (nicht pro Empfänger)');
  const pushB = await b.next('INSTANT_NEW');
  const pushC = await c.client.next('INSTANT_NEW');
  assert.equal(pushB.d.post.kind, 'instant');
  assert.equal(pushB.d.post.from, codeA);
  assert.equal(pushB.d.post.caption, 'Möhrenernte!');
  assert.equal(pushB.d.post.likes, 0);
  assert.equal(pushB.d.unseen, 1);
  assert.equal(pushC.d.post.id, pushB.d.post.id, 'derselbe Post für alle');
  const photoId = pushB.d.post.photoId;
  assert.ok(photoId.startsWith('instp-'));

  // kind-Trennung: der Post liegt in KEINEM Briefkasten …
  assert.equal((await b.request('MAIL_LIST', {})).d.total, 0, 'Post nicht im Postfach');
  // … und ein Brief taucht in KEINEM Feed auf (trägt aber kind:"mail").
  await a.request('MAIL_SEND', { to: codeB, text: 'echter Brief' });
  const brief = await b.next('MAIL_NEW');
  assert.equal(brief.d.mail.kind, 'mail', 'Briefe tragen das additive kind-Feld');
  const feedB = await b.request('FEED_LIST', {});
  assert.equal(feedB.d.total, 1, 'Brief landet nicht im Feed');
  assert.equal(feedB.d.posts[0].kind, 'instant');
  assert.equal(feedB.d.posts[0].mine, false);

  // Autor sieht den eigenen Post (mine:true), aber er zählt nicht als neu.
  const feedA = await a.request('FEED_LIST', {});
  assert.equal(feedA.d.posts[0].mine, true);
  assert.equal(feedA.d.unseen, 0, 'eigener Post ist nie „ungesehen“');

  // Boot-Pull über WELCOME.instantUnseen + FEED_ACK setzt das Badge zurück.
  const c2 = await WsClient.connect(server.wsUrl);
  t.after(() => c2.close());
  assert.equal((await c2.hello(c.id)).d.instantUnseen, 1);
  assert.equal((await c2.request('FEED_ACK', {})).d.unseen, 0);
  assert.equal((await c2.request('FEED_LIST', {})).d.unseen, 0);

  // Foto-Abruf: Empfänger UND Autor dürfen, Fremde/anonyme nicht.
  const asB = await fetch(`${server.url}/api/instant/blob/${photoId}`, {
    headers: { authorization: bearer(idB) },
  });
  assert.equal((await asB.json()).ok, true);
  const asA = await fetch(`${server.url}/api/instant/blob/${photoId}`, {
    headers: { authorization: bearer(idA) },
  });
  assert.equal((await asA.json()).ok, true);
  const fremd = newIdentity('Fremd');
  const w = await WsClient.connect(server.wsUrl);
  t.after(() => w.close());
  await w.hello(fremd);
  const asFremd = await fetch(`${server.url}/api/instant/blob/${photoId}`, {
    headers: { authorization: bearer(fremd) },
  });
  assert.equal(asFremd.status, 404);
  assert.equal((await fetch(`${server.url}/api/instant/blob/${photoId}`)).status, 401);
});

test('Instant: Foto-Pflicht, Caption-Limit, NO_FRIENDS, clientId-Dedupe', async (t) => {
  const { server, idA, codeB } = await twoFriends(t);

  // Ohne Foto geht nichts (Foto ist PFLICHT — anders als beim Brief).
  const ohneFoto = await postInstant(server, idA, { caption: 'nur Text' });
  assert.equal(ohneFoto.status, 400);
  assert.equal((await ohneFoto.json()).code, 'NO_PHOTO');

  // Caption über 120 Zeichen → CAPTION_TOO_LONG.
  const zuLang = await postInstant(server, idA, {
    caption: 'x'.repeat(CAPTION_MAX + 1),
    photoB64: fakePng().toString('base64'),
  });
  assert.equal(zuLang.status, 400);
  assert.equal((await zuLang.json()).code, 'CAPTION_TOO_LONG');

  // Ohne Freunde gibt es kein Publikum.
  const einsam = newIdentity('Einsam');
  const w = await WsClient.connect(server.wsUrl);
  t.after(() => w.close());
  await w.hello(einsam);
  const keineFreunde = await postInstant(server, einsam, {
    caption: 'hallo?',
    photoB64: fakePng().toString('base64'),
  });
  assert.equal(keineFreunde.status, 400);
  assert.equal((await keineFreunde.json()).code, 'NO_FRIENDS');

  // Outbox-Retry mit derselben clientId → dupe, zählt nicht doppelt.
  const clientId = 'instant-retry-0001';
  const erster = await postInstant(server, idA, {
    caption: 'nur einmal',
    photoB64: fakePng().toString('base64'),
    clientId,
  });
  assert.equal((await erster.json()).sentToday, 1);
  const retry = await postInstant(server, idA, {
    caption: 'nur einmal',
    photoB64: fakePng().toString('base64'),
    clientId,
  });
  const retryBody = await retry.json();
  assert.equal(retryBody.ok, true);
  assert.equal(retryBody.dupe, true);
  assert.equal(retryBody.sentToday, 1, 'Duplikat zählt nicht gegen die Quota');
  void codeB;
});

test('Instant-Quota: teilt die 20/Tag mit den Briefen, 1× pro Post', async (t) => {
  let now = 1_700_000_000_000;
  const { server, a, idA, codeB } = await twoFriends(t, { clock: { now: () => now } });

  // 19 Briefe + 1 Post = 20 → sowohl Post als auch Brief sind dann zu.
  for (let i = 0; i < DAILY_LIMIT - 1; i++) {
    const res = await a.request('MAIL_SEND', { to: codeB, text: `Brief ${i}` });
    assert.equal(res.d.ok, true);
  }
  const post = await postInstant(server, idA, {
    caption: 'der zwanzigste',
    photoB64: fakePng().toString('base64'),
  });
  assert.equal((await post.json()).sentToday, DAILY_LIMIT);
  const zuViel = await postInstant(server, idA, {
    caption: 'einer zu viel',
    photoB64: fakePng().toString('base64'),
  });
  assert.equal(zuViel.status, 429);
  assert.equal((await zuViel.json()).code, 'DAILY_LIMIT');
  const briefZu = await a.request('MAIL_SEND', { to: codeB, text: 'auch zu' });
  assert.equal(briefZu.d.code, 'DAILY_LIMIT', 'gemeinsame Quota sperrt auch Briefe');

  // Neuer Tag → frisch.
  now += DAY_MS;
  const frisch = await postInstant(server, idA, {
    caption: 'guten Morgen',
    photoB64: fakePng().toString('base64'),
  });
  assert.equal((await frisch.json()).sentToday, 1);
});

test('Feed-Ringpuffer: Cap 30 pro Empfänger, ältester fliegt samt Blob', async (t) => {
  let now = 1_700_000_000_000;
  const { server, b, idA } = await twoFriends(t, { clock: { now: () => now } });

  // 32 Posts über mehrere Tage (Quota 20/Tag) — Feed bleibt bei 30.
  const photoIds = [];
  for (let i = 0; i < FEED_CAP + 2; i++) {
    if (i > 0 && i % DAILY_LIMIT === 0) now += DAY_MS;
    now += 1000; // eindeutige at-Reihenfolge
    const res = await postInstant(server, idA, {
      caption: `Post ${i}`,
      photoB64: fakePng().toString('base64'),
    });
    assert.equal((await res.json()).ok, true, `Post ${i} zugestellt`);
    photoIds.push((await b.next('INSTANT_NEW')).d.post.photoId);
  }

  const feed = await b.request('FEED_LIST', {});
  assert.equal(feed.d.total, FEED_CAP, 'Ringpuffer hält den Feed bei 30');
  assert.equal(feed.d.cap, FEED_CAP);
  const captions = feed.d.posts.map((p) => p.caption);
  assert.equal(captions[0], `Post ${FEED_CAP + 1}`, 'jüngster zuerst');
  assert.ok(!captions.includes('Post 0'), 'ältester Post wurde verdrängt');
  assert.ok(!captions.includes('Post 1'), 'zweitältester Post wurde verdrängt');

  // Die Blobs der verdrängten Posts sind vom Teller (refs → 0), der Rest da.
  assert.equal(fs.existsSync(path.join(server.dataDir, 'instant', photoIds[0])), false);
  assert.equal(fs.existsSync(path.join(server.dataDir, 'instant', photoIds[1])), false);
  assert.equal(fs.existsSync(path.join(server.dataDir, 'instant', photoIds[2])), true);
});

test('Likes: 1 Möhre pro Freund pro Post, Push an den Autor, idempotent', async (t) => {
  const { server, a, b, idA, codeA, codeB } = await twoFriends(t);
  const c = await addFriend(t, server, a, codeA, 'Cleo');

  await postInstant(server, idA, {
    caption: 'Möhre da lassen?',
    photoB64: fakePng().toString('base64'),
  });
  const post = (await b.next('INSTANT_NEW')).d.post;
  await c.client.next('INSTANT_NEW');

  // Erster Like → ok + Push an den Autor.
  const like = await b.request('INSTANT_LIKE', { id: post.id });
  assert.equal(like.t, 'OK');
  assert.equal(like.d.likes, 1);
  const anAutor = await a.next('INSTANT_LIKE');
  assert.equal(anAutor.d.id, post.id);
  assert.equal(anAutor.d.by, codeB);
  assert.equal(anAutor.d.likes, 1);

  // Zweiter Like desselben Freundes → idempotent, KEIN zweiter Push.
  const nochmal = await b.request('INSTANT_LIKE', { id: post.id });
  assert.equal(nochmal.d.likes, 1);
  assert.equal(nochmal.d.already, true);
  assert.equal(
    a.inbox.filter((m) => m.t === 'INSTANT_LIKE').length,
    0,
    'kein Doppel-Push an den Autor'
  );

  // Zweiter Freund darf noch — Zähler steigt auf 2.
  const zweite = await c.client.request('INSTANT_LIKE', { id: post.id });
  assert.equal(zweite.d.likes, 2);
  assert.equal((await a.next('INSTANT_LIKE')).d.likes, 2);

  // Autor kann sich selbst keine Möhre da lassen; Fremde sehen den Post nicht.
  assert.equal((await a.request('INSTANT_LIKE', { id: post.id })).d.code, 'SELF');
  const fremd = await WsClient.connect(server.wsUrl);
  t.after(() => fremd.close());
  await fremd.hello(newIdentity('Fremd'));
  assert.equal((await fremd.request('INSTANT_LIKE', { id: post.id })).d.code, 'NOT_FOUND');

  // liked-Flag ist Betrachter-abhängig in FEED_STATE.
  const feedB = await b.request('FEED_LIST', {});
  assert.equal(feedB.d.posts[0].liked, true);
  assert.equal(feedB.d.posts[0].likes, 2);
});
