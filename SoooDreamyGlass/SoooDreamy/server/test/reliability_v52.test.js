import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Store } from '../src/store.js';
import { dateKeyDaysAgo, makeApp, setupCouple, wsOpen } from './helpers.js';

test('legacy JSON is compacted into lossless per-couple segments at startup', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-segments-'));
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const legacy = {
    version: 1,
    couples: {
      c_one: {
        id: 'c_one',
        code: 'ONEOLD',
        members: [{ id: 'member' }],
        messages: [{ id: 'm1', text: 'keep me' }],
      },
      c_two: {
        id: 'c_two',
        code: 'TWOOLD',
        members: [{ id: 'member-two' }],
        messages: [{ id: 'm2', text: 'keep me too' }],
      },
    },
    tokens: { digest: { coupleId: 'c_one', memberId: 'member' } },
  };
  await writeFile(path.join(dataDir, 'store.json'), JSON.stringify(legacy, null, 8));

  const store = await new Store({ dataDir }).init();
  const manifest = JSON.parse(await readFile(path.join(dataDir, 'store.json'), 'utf8'));
  assert.equal(manifest.format, 'segmented-v1');
  assert.deepEqual(Object.keys(manifest.couples).sort(), ['c_one', 'c_two']);
  assert.deepEqual(store.data.couples, legacy.couples);
  assert.deepEqual(store.data.tokens, legacy.tokens);

  store.data.couples.c_one.messages.push({ id: 'm3', text: 'new' });
  store.markDirty();
  await store.close();

  const reopened = await new Store({ dataDir }).init();
  assert.deepEqual(reopened.data.couples.c_one.messages.map((message) => message.id), ['m1', 'm3']);
  assert.equal(reopened.data.couples.c_two.messages[0].text, 'keep me too');
  const stats = await reopened.storageStats();
  assert.equal(stats.format, 'segmented-v1');
  assert.equal(stats.couples, 2);
  assert.equal(stats.segmentFiles, 2);
  assert.ok(stats.segmentBytes > 0);
  await reopened.close();
});

test('health reports bounded storage and media quota statistics', async (t) => {
  const { baseUrl, app } = await makeApp(t, { mediaQuotaBytes: 1_000 });
  await app.store.saveMedia('photos', 'quota-test.jpg', Buffer.alloc(250));
  const health = await fetch(`${baseUrl}/api/health`).then((response) => response.json());
  assert.equal(health.ok, true);
  assert.equal(health.storage.mediaBytes, 250);
  assert.equal(health.storage.mediaFiles, 1);
  assert.equal(health.storage.mediaQuotaBytes, 1_000);
  assert.equal(health.storage.mediaQuotaUsed, 0.25);
});

test('reaction and daily retries are exactly-once with client operation ids', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const socket = await wsOpen(baseUrl, b.token, t);
  await socket.waitFor('welcome');
  const message = (await a.api.post('/api/messages', {
    json: { type: 'text', text: 'react once' },
  })).body.message;
  await socket.waitFor('message');

  const reactionBody = { emoji: '💜', clientOperationId: 'reaction-offline-1' };
  const firstReaction = await a.api.post(`/api/messages/${message.id}/reactions`, { json: reactionBody });
  const reactionFrame = await socket.waitFor('message_updated');
  const retriedReaction = await a.api.post(`/api/messages/${message.id}/reactions`, { json: reactionBody });
  assert.equal(firstReaction.status, 200);
  assert.equal(retriedReaction.status, 200);
  assert.equal(retriedReaction.body.duplicate, true);
  assert.deepEqual(retriedReaction.body.message.reactions['💜'], [a.memberId]);
  assert.deepEqual(reactionFrame.payload.message.reactions['💜'], [a.memberId]);
  await socket.assertNone('message_updated');

  const dailyBody = {
    questionId: 42,
    text: 'first answer survives a lost response',
    clientOperationId: 'daily-offline-1',
  };
  const today = dateKeyDaysAgo(0);
  assert.equal((await a.api.post(`/api/daily/${today}`, { json: dailyBody })).status, 200);
  await socket.waitFor('daily_answer');
  const retriedDaily = await a.api.post(`/api/daily/${today}`, {
    json: { ...dailyBody, text: 'must not overwrite' },
  });
  assert.equal(retriedDaily.status, 200);
  assert.equal(retriedDaily.body.duplicate, true);
  assert.equal(retriedDaily.body.myAnswer, dailyBody.text);
  await socket.assertNone('daily_answer');
});
