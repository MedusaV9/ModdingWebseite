// Lens 45 — error contract: every code the server can emit is documented in
// docs/API.md (the iOS client builds its error mapping from that catalog),
// and time-boxed 429s carry a machine-readable retry-after header.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { readdir, readFile } from 'node:fs/promises';
import { makeApp, client, setupCouple } from './helpers.js';

const here = dirname(fileURLToPath(import.meta.url));
const srcRoot = resolve(here, '../src');
const apiDoc = resolve(here, '../../docs/API.md');

async function serverSources(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const path = join(directory, entry.name);
    // admin/public is browser code — it consumes errors, it never emits them.
    if (entry.isDirectory()) return entry.name === 'public' ? [] : serverSources(path);
    return path.endsWith('.js') ? [path] : [];
  }));
  return nested.flat();
}

test('every error code the server emits is documented in the API.md catalog', async () => {
  const codes = new Set(['internal_error']); // 500 fallback in the router catch-all
  for (const file of await serverSources(srcRoot)) {
    const source = await readFile(file, 'utf8');
    // httpError(status, 'code', …) and new HttpError(status, 'code', …)
    for (const m of source.matchAll(/(?:httpError|new HttpError)\(\s*\d+\s*,\s*'([a-z0-9_]+)'/g)) {
      codes.add(m[1]);
    }
    // game-rules.js reject('code', …) sugar
    for (const m of source.matchAll(/reject\(\s*'([a-z0-9_]+)'/g)) {
      codes.add(m[1]);
    }
  }
  assert.ok(codes.size >= 130, `expected the full catalog, scanned only ${codes.size} codes`);

  const doc = await readFile(apiDoc, 'utf8');
  assert.ok(doc.includes('## Error code catalog'), 'API.md must contain the error code catalog section');
  const undocumented = [...codes].filter((code) => !doc.includes(`\`${code}\``)).sort();
  assert.deepEqual(undocumented, [], 'new error codes must be added to the API.md catalog');
});

test('error responses stay machine-readable: {error, message} on every failure shape', async (t) => {
  const { baseUrl } = await makeApp(t);
  const anon = client(baseUrl);

  const unknownRoute = await anon.get('/api/definitely-not-a-route');
  assert.equal(unknownRoute.status, 404);
  assert.equal(unknownRoute.body.error, 'not_found');
  assert.equal(typeof unknownRoute.body.message, 'string');

  const badJson = await anon.post('/api/couples', {
    body: '{nope', headers: { 'content-type': 'application/json' },
  });
  assert.equal(badJson.status, 400);
  assert.equal(badJson.body.error, 'invalid_json');

  const noToken = await anon.get('/api/couple');
  assert.equal(noToken.status, 401);
  assert.equal(noToken.body.error, 'invalid_token');
});

test('effect cooldown answers 429 with a retry-after countdown', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const first = await a.api.post('/api/messages', {
    json: { type: 'text', text: 'boom', effect: 'fireworks' },
  });
  assert.equal(first.status, 201);

  const second = await a.api.post('/api/messages', {
    json: { type: 'text', text: 'again', effect: 'hearts' },
  });
  assert.equal(second.status, 429);
  assert.equal(second.body.error, 'effect_cooldown');
  const retryAfter = Number(second.headers.get('retry-after'));
  assert.ok(Number.isInteger(retryAfter), 'retry-after must be an integer number of seconds');
  assert.ok(retryAfter >= 1 && retryAfter <= 12, `retry-after within the 12s cooldown, got ${retryAfter}`);
});

test('pulse cooldown answers 429 with a retry-after countdown', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const first = await a.api.post('/api/pulses', { json: { kind: 'thinking' } });
  assert.equal(first.status, 201);

  const second = await a.api.post('/api/pulses', { json: { kind: 'heartbeat' } });
  assert.equal(second.status, 429);
  assert.equal(second.body.error, 'too_soon');
  const retryAfter = Number(second.headers.get('retry-after'));
  assert.ok(Number.isInteger(retryAfter), 'retry-after must be an integer number of seconds');
  assert.ok(retryAfter >= 1 && retryAfter <= 30, `retry-after within the 30s cooldown, got ${retryAfter}`);
});

test('request rate limiter answers 429 rate_limited with retry-after', async (t) => {
  // coupleCreate allows 5 per hour per IP — the sixth attempt must be throttled.
  const { baseUrl } = await makeApp(t);
  const anon = client(baseUrl);
  let limited = null;
  for (let i = 0; i < 6 && !limited; i += 1) {
    const res = await anon.post('/api/couples', {
      json: { name: `M${i}`, avatar: '🦊', color: '#FF5C8A' },
    });
    if (res.status === 429) limited = res;
  }
  assert.ok(limited, 'the sixth couple-create from one IP should be throttled');
  assert.equal(limited.body.error, 'rate_limited');
  const retryAfter = Number(limited.headers.get('retry-after'));
  assert.ok(Number.isInteger(retryAfter) && retryAfter >= 1, `retry-after present, got ${retryAfter}`);
});
