// Analytics: REST-Batch-Ingest (idempotent über batchId + sessionId), Aggregation
// Spielzeit pro Tag/Spieler, JSONL-Rohlog.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient, bearer } from './helpers.js';
import { analyticsData } from '../src/analytics.js';
import { dayKey } from '../src/config.js';

async function connectedIdentity(server, name = 'Anna') {
  const id = newIdentity(name);
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(id);
  return { id, c };
}

function postAnalytics(server, id, body) {
  return fetch(`${server.url}/api/analytics`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: bearer(id) },
    body: JSON.stringify(body),
  });
}

test('Batch-Ingest + Idempotenz: gleicher batchId zählt nie doppelt', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const { id, c } = await connectedIdentity(server);
  t.after(() => c.close());
  const base = Date.UTC(2026, 6, 20, 10, 0, 0);
  const batch = {
    batchId: 'batch-0001',
    sessions: [
      { sessionId: 'sess-a1', startedAt: base, endedAt: base + 30 * 60_000, minutes: 30 },
      { sessionId: 'sess-a2', startedAt: base + 3600_000, endedAt: base + 3600_000 + 15 * 60_000, minutes: 15 },
    ],
  };
  const r1 = await (await postAnalytics(server, id, batch)).json();
  assert.deepEqual({ ok: r1.ok, accepted: r1.accepted, duplicates: r1.duplicates }, { ok: true, accepted: 2, duplicates: 0 });
  // Identischer Batch nochmal (Offline-Flush-Retry) → idempotent.
  const r2 = await (await postAnalytics(server, id, batch)).json();
  assert.equal(r2.accepted, 0);
  assert.equal(r2.duplicates, 2);
  // Gleiche Session in NEUEM Batch → sessionId-Dedupe.
  const r3 = await (
    await postAnalytics(server, id, { batchId: 'batch-0002', sessions: [batch.sessions[0]] })
  ).json();
  assert.equal(r3.accepted, 0);
  assert.equal(r3.duplicates, 1);

  // Aggregation: genau 45 Minuten / 2 Sessions an genau einem Tag.
  const data = analyticsData(server.ctx);
  const day = dayKey(base + 30 * 60_000, server.ctx.cfg.tz);
  assert.equal(data.days[day][id.deviceId].minutes, 45);
  assert.equal(data.days[day][id.deviceId].sessions, 2);
  assert.equal(data.perPlayer[id.deviceId].minutes, 45);
  assert.equal(data.perPlayer[id.deviceId].sessions, 2);
});

test('Aggregation pro Tag & Spieler (wann/wie lange/wie oft)', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const { id: anna, c: ca } = await connectedIdentity(server, 'Anna');
  const { id: ben, c: cb } = await connectedIdentity(server, 'Ben');
  t.after(() => [ca, cb].forEach((c) => c.close()));
  const day1 = Date.UTC(2026, 6, 20, 9, 0, 0);
  const day2 = Date.UTC(2026, 6, 21, 18, 0, 0);
  const r1 = await (
    await postAnalytics(server, anna, {
      batchId: 'batch-anna',
      sessions: [
        { sessionId: 'sess-0001', startedAt: day1, endedAt: day1 + 60 * 60_000, minutes: 60 },
        { sessionId: 'sess-0002', startedAt: day2, endedAt: day2 + 20 * 60_000, minutes: 20 },
      ],
    })
  ).json();
  assert.equal(r1.accepted, 2);
  const r2 = await (
    await postAnalytics(server, ben, {
      batchId: 'batch-ben',
      sessions: [
        { sessionId: 'sess-0003', startedAt: day1 + 3600_000, endedAt: day1 + 2 * 3600_000, minutes: 60 },
      ],
    })
  ).json();
  assert.equal(r2.accepted, 1);
  const data = analyticsData(server.ctx);
  const tz = server.ctx.cfg.tz;
  assert.equal(data.days[dayKey(day1 + 60 * 60_000, tz)][anna.deviceId].minutes, 60);
  assert.equal(data.days[dayKey(day2, tz)][anna.deviceId].minutes, 20);
  assert.equal(data.days[dayKey(day1 + 2 * 3600_000, tz)][ben.deviceId].sessions, 1);
  assert.equal(data.perPlayer[anna.deviceId].sessions, 2);
  // "Wann": Stunden-Histogramm zählt Session-STARTS (Berlin: 9:00 UTC = 11 Uhr).
  assert.equal(data.hours['11'] >= 1, true);
  // Rohlog geschrieben.
  const lines = server.ctx.store.readLines(`sessions/sessions-${dayKey(day1, tz).slice(0, 7)}.jsonl`);
  assert.equal(lines.length >= 2, true);
});

test('Härtung: Auth Pflicht, Batch-Limits, kaputte Sessions überspringen', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const { id, c } = await connectedIdentity(server);
  t.after(() => c.close());

  const noAuth = await fetch(`${server.url}/api/analytics`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ batchId: 'x-123456', sessions: [] }),
  });
  assert.equal(noAuth.status, 401);

  const tooMany = await postAnalytics(server, id, {
    batchId: 'big-00001',
    sessions: Array.from({ length: 201 }, (_, i) => ({
      sessionId: `s-${i}-xxxxx`,
      startedAt: 1,
      endedAt: 2,
    })),
  });
  assert.equal(tooMany.status, 400);
  assert.equal((await tooMany.json()).code, 'BATCH_TOO_LARGE');

  const badBatch = await postAnalytics(server, id, { batchId: '!!', sessions: [{}] });
  assert.equal(badBatch.status, 400);

  // Kaputte Einzel-Session (endedAt < startedAt) wird übersprungen, Rest zählt.
  const mixed = await (
    await postAnalytics(server, id, {
      batchId: 'mix-00001',
      sessions: [
        { sessionId: 'ok-000001', startedAt: 1000, endedAt: 61_000, minutes: 1 },
        { sessionId: 'bad-00001', startedAt: 61_000, endedAt: 1000 },
      ],
    })
  ).json();
  assert.equal(mixed.accepted, 1);
});
