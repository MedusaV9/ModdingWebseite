import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Buckets, LIMITS } from '../src/ratelimit.js';

test('Token-Bucket: Kapazität, Verbrauch, Refill (deterministisch mit Fake-Zeit)', () => {
  let now = 1_000_000;
  const buckets = new Buckets(() => now);
  const limit = { capacity: 5, refillPerSec: 1 };
  for (let i = 0; i < 5; i++) assert.equal(buckets.take('k', limit), true, `take ${i}`);
  assert.equal(buckets.take('k', limit), false, 'leer → abgelehnt');
  now += 2_000; // 2 Tokens nachgefüllt
  assert.equal(buckets.take('k', limit), true);
  assert.equal(buckets.take('k', limit), true);
  assert.equal(buckets.take('k', limit), false);
  now += 60 * 60_000; // Refill ist auf capacity gedeckelt
  for (let i = 0; i < 5; i++) assert.equal(buckets.take('k', limit), true);
  assert.equal(buckets.take('k', limit), false);
});

test('Token-Bucket: Keys sind unabhängig', () => {
  let now = 0;
  const buckets = new Buckets(() => now);
  const limit = { capacity: 1, refillPerSec: 0 };
  assert.equal(buckets.take('a', limit), true);
  assert.equal(buckets.take('a', limit), false);
  assert.equal(buckets.take('b', limit), true);
});

test('Limit-Presets: Doc-C-Werte vorhanden', () => {
  assert.equal(LIMITS.hello.capacity, 5); // 5/min pro IP
  assert.equal(LIMITS.friendRequest.capacity, 10); // 10/h
  assert.equal(LIMITS.palSend.capacity, 20); // 20/h
  assert.equal(LIMITS.codesRedeem.capacity, 5); // 5/15min
  assert.equal(LIMITS.panelLogin.capacity, 5); // 5/15min
  assert.equal(LIMITS.roomPos.refillPerSec, 5); // POS 5 Hz
});
