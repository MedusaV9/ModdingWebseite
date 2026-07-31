// Panel-Ausbau W13-C (Befund P3): die drei neuen Seiten (GoobyPal-Ledger,
// Spiele & Besuche, Ranch-Bestenlisten) rendern echte Server-Daten — Pal-Ledger
// mit Suche/Tagessummen/Top-Sendern aus dem JSONL-Ledger, Brettspiel-Zustand
// direkt aus ctx.boardGames, Besuchs-Log aus der neuen visits-Collection,
// Ranch-Bestenlisten aus ranchscores. Spieler-Seite trägt die neuen Spalten.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { twoFriends, bearer } from './helpers.js';

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

async function getPage(server, cookie, path) {
  const res = await fetch(`${server.url}${path}`, { headers: { cookie } });
  assert.equal(res.status, 200, path);
  return res.text();
}

test('Pal-Ledger-Seite: Transfers, Filter (Von/An/Betrag/Datum), Tagessummen, Top-Sender', async (t) => {
  const { server, a, codeA, codeB } = await twoFriends(t, { env: { GOOBY_ADMIN_PASSWORD: PW } });
  const pal = await a.request('PAL_SEND', { to: codeB, amount: 40 });
  assert.equal(pal.d.ok, true);
  const cookie = await login(server);

  const page = await getPage(server, cookie, '/panel/pal');
  assert.match(page, /GoobyPal-Transfers durchsuchen/);
  assert.match(page, new RegExp(`Anna \\(${codeA}\\)`), 'Sender aufgelöst');
  assert.match(page, new RegExp(`Ben \\(${codeB}\\)`), 'Empfänger aufgelöst');
  assert.match(page, /<td>40<\/td>/, 'Betrag in der Tabelle');
  assert.match(page, /Tagessummen/);
  assert.match(page, /Top-Sender/);
  assert.match(page, /1 Transfer\(s\) gefunden/);

  // Filter: Von=codeA trifft, Von=codeB nicht; Betrag-Minimum filtert.
  const hit = await getPage(server, cookie, `/panel/pal?von=${encodeURIComponent(codeA)}`);
  assert.match(hit, /1 Transfer\(s\) gefunden/);
  const miss = await getPage(server, cookie, `/panel/pal?von=${encodeURIComponent(codeB)}`);
  assert.match(miss, /0 Transfer\(s\) gefunden/);
  assert.match(miss, /Keine Transfers gefunden/);
  const tooBig = await getPage(server, cookie, '/panel/pal?min=41');
  assert.match(tooBig, /0 Transfer\(s\) gefunden/);
  const anHit = await getPage(server, cookie, `/panel/pal?an=${encodeURIComponent(codeB)}&min=40`);
  assert.match(anHit, /1 Transfer\(s\) gefunden/);
});

test('Spiele & Besuche: laufende Partie aus ctx.boardGames + Besuchs-Log mit Dauer', async (t) => {
  const clock = { t: Date.now(), now() { return this.t; } };
  const { server, a, b, codeA, codeB } = await twoFriends(t, {
    env: { GOOBY_ADMIN_PASSWORD: PW },
    clock,
  });
  const cookie = await login(server);

  // Brettspiel starten (Invite → Accept → BOARD_START).
  await a.request('BOARD_INVITE', { target: codeB, game: 'battleship' });
  await b.next('BOARD_INVITED');
  const start = await b.request('BOARD_ACCEPT', { from: codeA });
  assert.equal(start.t, 'BOARD_START');

  let page = await getPage(server, cookie, '/panel/spiele');
  assert.match(page, /Schiffe versenken/);
  assert.match(page, new RegExp(`Anna \\(${codeA}\\)`));
  assert.match(page, new RegExp(`Ben \\(${codeB}\\)`));
  assert.match(page, /läuft/);

  // Besuch: Anna besucht Ben → Log-Eintrag "läuft"; nach VISIT_END mit Dauer.
  await a.request('VISIT_REQUEST', { target: codeB });
  await b.next('VISIT_INCOMING');
  const ready = await b.request('VISIT_ACCEPT', { guest: codeA });
  assert.equal(ready.t, 'VISIT_READY');
  page = await getPage(server, cookie, '/panel/spiele');
  assert.match(page, /Besuchs-Log/);
  const gastZeile = new RegExp(`Anna \\(${codeA}\\)</td><td>Ben \\(${codeB}\\)`);
  assert.match(page, gastZeile, 'Gast bei Host');

  clock.t += 7 * 60_000; // 7 Minuten Besuch (zeitinjiziert)
  await a.request('PING'); // Heartbeat frisch halten (Idle-Wächter nutzt clock)
  await b.request('PING');
  await b.request('VISIT_END', {});
  page = await getPage(server, cookie, '/panel/spiele');
  assert.match(page, /7 min/, 'Besuchs-Dauer nach dem Ende');

  // Persistiert: der Log-Eintrag steht in der visits-Collection.
  const log = server.ctx.store.collection('visits', { log: [] }).log;
  assert.equal(log.length, 1);
  assert.equal(log[0].host, codeB);
  assert.equal(log[0].guest, codeA);
  assert.ok(Number.isFinite(log[0].endedAt));
});

test('Ranch-Bestenlisten: rw5-Wertung als Top-10-Tabelle (Zeitformat, Namen)', async (t) => {
  const { server, idA, codeA } = await twoFriends(t, { env: { GOOBY_ADMIN_PASSWORD: PW } });
  const cookie = await login(server);

  // Leer-Zustand.
  let page = await getPage(server, cookie, '/panel/ranch');
  assert.match(page, /Noch keine Bestenlisten/);

  // Asynchrone Bestzeit melden (REST, wie der Client) → Tabelle erscheint.
  const res = await fetch(`${server.url}/api/rmp/score`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: bearer(idA) },
    body: JSON.stringify({ kurs: 'rw5_rennen', zeitMs: 65_000 }),
  });
  assert.equal((await res.json()).ok, true);

  page = await getPage(server, cookie, '/panel/ranch');
  assert.match(page, /rw5_rennen/);
  assert.match(page, /schnellste Zeit/);
  assert.match(page, new RegExp(`Anna \\(${codeA}\\)`));
  assert.match(page, /1:05,000/, 'Zeitformat min:sek,ms');
});

test('Navigation + Spieler-Seite: neue Seiten verlinkt, Status-/Aktionen-Spalten da', async (t) => {
  const { server } = await twoFriends(t, { env: { GOOBY_ADMIN_PASSWORD: PW } });
  const cookie = await login(server);
  const dash = await getPage(server, cookie, '/panel/');
  for (const href of ['/panel/pal', '/panel/spiele', '/panel/ranch']) {
    assert.ok(dash.includes(`href="${href}"`), `Nav enthält ${href}`);
  }
  const players = await getPage(server, cookie, '/panel/players');
  assert.match(players, /<th>Status<\/th>/);
  assert.match(players, /<th>Aktionen<\/th>/);
  assert.match(players, /Bannen/);
  assert.match(players, /Umzugs-Code/);
  assert.match(players, /Moderations-Audit/);
});
