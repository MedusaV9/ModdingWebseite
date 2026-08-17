import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { APP_ERROR_CODES, APP_EVENT_TYPES } from '../src/events.js';

// EVAL-3.0 P1: docs/API.md documented event types that never existed
// (daymemo_streak) and wrong names (goal_completed, weekplan_slot,
// still_sealed). This contract test pins the docs to the canonical registry
// so they cannot drift again.

const apiDoc = await readFile(new URL('../../docs/API.md', import.meta.url), 'utf8');

test('the canonical app-event registry exactly matches docs/API.md', () => {
  const block = apiDoc.match(/<!-- APP_EVENT_TYPES:START -->([\s\S]*?)<!-- APP_EVENT_TYPES:END -->/);
  assert.ok(block, 'docs/API.md is missing its canonical APP_EVENT_TYPES block');
  const documented = [...block[1].matchAll(/`([a-z_]+)`/g)].map((match) => match[1]);
  assert.deepEqual(documented, APP_EVENT_TYPES);
});

test('docs/API.md names no phantom or renamed app-event types', () => {
  // Historic wrong names from the 3.0 docs — must never come back.
  for (const phantom of ['daymemo_streak', 'goal_completed`', '`weekplan_slot`', 'still_sealed']) {
    assert.ok(!apiDoc.includes(phantom), `docs/API.md still mentions "${phantom}" (stale/renamed)`);
  }
});

test('the capsule lock error code in the docs matches the server (still_locked)', async () => {
  const rituals = await readFile(new URL('../src/rituals.js', import.meta.url), 'utf8');
  const code = APP_ERROR_CODES.capsuleStillLocked;
  assert.ok(rituals.includes('APP_ERROR_CODES.capsuleStillLocked'));
  assert.ok(apiDoc.includes(`\`${code}\``));
});

test('the registry matches what the source actually emits', async () => {
  const sources = await Promise.all(
    [
      '../src/rituals.js',
      '../src/router.js',
      '../src/platform.js',
      '../src/gamification.js',
      '../src/warmth.js',
      '../src/seasonal.js',
      '../src/weekreview.js',
    ].map((p) =>
      readFile(new URL(p, import.meta.url), 'utf8'),
    ),
  );
  const code = sources.join('\n');
  // Collect the string literals of each call site's `type:` expression
  // (plain literals and ternaries like `m === 100 ? 'a' : 'b'`).
  const emitted = new Set();
  for (const site of code.matchAll(/emitAppEvent\(\{[\s\S]{0,400}?type:([^\n]*)/g)) {
    for (const literal of site[1].matchAll(/'([a-z_]+)'/g)) emitted.add(literal[1]);
  }
  for (const type of emitted) {
    assert.ok(APP_EVENT_TYPES.includes(type), `emitted type "${type}" is missing from APP_EVENT_TYPES`);
  }
  for (const type of APP_EVENT_TYPES) {
    assert.ok(emitted.has(type), `registry type "${type}" is never emitted by the server`);
  }
});
