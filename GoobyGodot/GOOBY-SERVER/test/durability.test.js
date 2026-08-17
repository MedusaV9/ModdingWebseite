// Crash-Durability (E13 P1-1/P1-2): bestätigte Mutationen (Code-Redeem, Analytics-Batch,
// Pal-Gutschrift) müssen einen Prozessabsturz DIREKT nach der Erfolgsantwort überleben —
// das Write-behind-Fenster ist für diese Klasse 0 (Storage.flushNow vor dem ok).
// helpers.crash() beendet den Server hart OHNE Storage-Flush (wie ein echter Crash);
// der Neustart läuft auf demselben dataDir.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient, bearer, twoFriends } from './helpers.js';
import { createCode } from '../src/codes.js';
import { analyticsData } from '../src/analytics.js';

function postJson(url, identity, body) {
  return fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: bearer(identity) },
    body: JSON.stringify(body),
  });
}

test('Redeem-Crash: eingelöst bleibt eingelöst — nach Neustart ALREADY_REDEEMED', async (t) => {
  // Phase 1: Account + Code normal anlegen, sauber stoppen (Basiszustand auf Platte).
  const s1 = await startServer();
  const dataDir = s1.dataDir;
  const id = newIdentity('Anna');
  const c1 = await WsClient.connect(s1.wsUrl);
  await c1.hello(id);
  c1.close();
  createCode(s1.ctx, { code: 'CRASH26', reward: { coins: 500 }, maxUses: 1 });
  await s1.stop({ keepData: true });

  // Phase 2: Redeem → ok:true, dann Absturz OHNE Write-behind-Flush.
  const s2 = await startServer({ dataDir });
  const r1 = await (await postJson(`${s2.url}/api/codes/redeem`, id, { code: 'CRASH26' })).json();
  assert.equal(r1.ok, true);
  assert.deepEqual(r1.reward, { coins: 500 });
  await s2.crash();

  // Phase 3: Neustart → der redeemed-Marker wurde VOR dem ok persistiert.
  const s3 = await startServer({ dataDir });
  t.after(() => s3.stop());
  const r2 = await (await postJson(`${s3.url}/api/codes/redeem`, id, { code: 'CRASH26' })).json();
  assert.equal(r2.ok, false);
  assert.equal(r2.code, 'ALREADY_REDEEMED');
});

test('Analytics-Crash: batchId/sessionId-Idempotenz überlebt den Neustart', async (t) => {
  const s1 = await startServer();
  const dataDir = s1.dataDir;
  const id = newIdentity('Anna');
  const c1 = await WsClient.connect(s1.wsUrl);
  await c1.hello(id);
  c1.close();
  await s1.stop({ keepData: true });

  const base = Date.UTC(2026, 6, 20, 10, 0, 0);
  const batch = {
    batchId: 'crash-batch-01',
    sessions: [{ sessionId: 'crash-sess-01', startedAt: base, endedAt: base + 600_000, minutes: 10 }],
  };
  const s2 = await startServer({ dataDir });
  const r1 = await (await postJson(`${s2.url}/api/analytics`, id, batch)).json();
  assert.deepEqual({ ok: r1.ok, accepted: r1.accepted }, { ok: true, accepted: 1 });
  await s2.crash();

  // Neustart: derselbe Batch UND dieselbe Session in neuem Batch sind Duplikate —
  // nichts wird doppelt gezählt (vor dem Fix: erneut accepted:1).
  const s3 = await startServer({ dataDir });
  t.after(() => s3.stop());
  const r2 = await (await postJson(`${s3.url}/api/analytics`, id, batch)).json();
  assert.equal(r2.accepted, 0);
  assert.equal(r2.duplicates, 1);
  const r3 = await (
    await postJson(`${s3.url}/api/analytics`, id, {
      batchId: 'crash-batch-02',
      sessions: batch.sessions,
    })
  ).json();
  assert.equal(r3.accepted, 0);
  assert.equal(r3.duplicates, 1);
  // Aggregation blieb bei genau EINER 10-Minuten-Session.
  const data = analyticsData(s3.ctx);
  assert.equal(data.perPlayer[id.deviceId].minutes, 10);
  assert.equal(data.perPlayer[id.deviceId].sessions, 1);
});

test('Pal-Crash: Gutschrift (ok:true) überlebt Absturz → Pull beim nächsten Connect', async (t) => {
  const { server, a, b, codeB, idB } = await twoFriends(t);
  b.close();
  await b.waitClose();
  const res = await a.request('PAL_SEND', { to: codeB, amount: 42 });
  assert.equal(res.d.ok, true);
  // Absturz DIREKT nach der Bestätigung an den Absender.
  await server.crash();

  const s2 = await startServer({ dataDir: server.dataDir });
  const b2 = await WsClient.connect(s2.wsUrl);
  const welcome = await b2.hello(idB);
  assert.equal(welcome.d.palPending.length, 1);
  assert.equal(welcome.d.palPending[0].amount, 42);
  assert.equal(typeof welcome.d.palPending[0].id, 'string');
  b2.close();
  // Explizit VOR den twoFriends-Hooks stoppen (geteiltes dataDir; das
  // Verzeichnis räumt der twoFriends-after ab).
  await s2.stop({ keepData: true });
});
