// Sync contract h (FX-S) — the eval battery found manifest drift: the server
// knew 28 game types, iOS 25, the Play-Hub 27. The canonical list is now
// machine-readable (GET /api/games/catalog) and DRIFT-WATCHED: the ```gametypes
// block in docs/API.md ("Game manifest") must stay byte-identical to
// GAME_TYPES in src/game-rules.js, so the documented truth can never rot.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { GAME_TYPES } from '../src/game-rules.js';
import { client, makeApp, setupCouple } from './helpers.js';

test('GET /api/games/catalog exports the canonical 28-type manifest (auth required)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const catalog = await a.api.get('/api/games/catalog');
  assert.equal(catalog.status, 200);
  assert.deepEqual(catalog.body, { types: [...GAME_TYPES] });
  assert.equal(catalog.body.types.length, 28, 'the canonical list has exactly 28 types');

  // Same auth story as every other games route.
  const anon = await client(baseUrl).get('/api/games/catalog');
  assert.equal(anon.status, 401);
});

test('DRIFT WATCHER: the gametypes block in docs/API.md pins GAME_TYPES exactly', async () => {
  const doc = await readFile(new URL('../../docs/API.md', import.meta.url), 'utf8');
  const blocks = [...doc.matchAll(/```gametypes\n([\s\S]*?)```/g)];
  assert.equal(blocks.length, 1, 'docs/API.md must contain exactly ONE ```gametypes block');
  const documented = blocks[0][1].trim().split('\n').map((line) => line.trim());
  // Order matters too — the catalog endpoint promises server order.
  assert.deepEqual(
    documented,
    [...GAME_TYPES],
    'GAME_TYPES (src/game-rules.js) and the "Game manifest" list in docs/API.md drifted apart — update BOTH together',
  );
});

test('every catalog type is registered end-to-end at POST /api/games', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  // The inverse first (before the loop eats into the create rate budget):
  // an off-catalog type IS the unknown enum.
  const unknown = await a.api.post('/api/games', { json: { type: 'schnick' } });
  assert.equal(unknown.status, 400);
  assert.equal(unknown.body.error, 'invalid_type');
  for (const type of GAME_TYPES) {
    const created = await a.api.post('/api/games', { json: { type } });
    // The manifest promise: NO catalog type bounces as an unknown enum. Types
    // with content preconditions may refuse with a DOMAIN error (photomemory
    // needs 2–8 gallery photos) — that still proves the type is wired up.
    assert.notEqual(created.body.error, 'invalid_type', `${type} must be a known type`);
    if (created.status === 201) {
      assert.equal(created.body.game.type, type);
      // End it (decline) so the one-open-session-per-type cap never bites.
      const ended = await b.api.post(`/api/games/${created.body.game.id}/end`, { json: {} });
      assert.equal(ended.status, 200, `${type}: ${JSON.stringify(ended.body)}`);
    }
  }
});
