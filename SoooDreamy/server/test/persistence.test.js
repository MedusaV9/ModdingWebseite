import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { makeApp, client, setupCouple } from './helpers.js';

test('data survives close() + reopen with the same DATA_DIR (flush on close)', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-persist-'));
  t.after(() => rm(dataDir, { recursive: true, force: true }));

  // --- first app lifetime: write data, close (debounce must be flushed) ---
  const first = await makeApp(t, { dataDir });
  const { a, b, coupleId } = await setupCouple(first.baseUrl);
  await a.api.patch('/api/couple', { json: { name: 'Mia & Ben', anniversary: '2023-11-07' } });
  const msg = (await a.api.post('/api/messages', { json: { type: 'text', text: 'remember me' } })).body.message;
  const voice = (
    await b.api.post('/api/voice', {
      body: Buffer.from('voice-bytes'),
      headers: { 'content-type': 'audio/mp4', 'x-duration-sec': '3.5' },
    })
  ).body.message;
  await first.close(); // immediately after writing — relies on flush-on-close

  // store.json exists and has the expected top-level shape
  const raw = JSON.parse(await readFile(path.join(dataDir, 'store.json'), 'utf8'));
  assert.deepEqual(Object.keys(raw).sort(), ['couples', 'tokens', 'version']);
  assert.ok(raw.couples[coupleId]);

  // --- second app lifetime: same DATA_DIR, old tokens still valid ---
  const second = await makeApp(t, { dataDir });
  const aApi = client(second.baseUrl, a.token);

  const coupleRes = await aApi.get('/api/couple');
  assert.equal(coupleRes.status, 200);
  assert.equal(coupleRes.body.couple.id, coupleId);
  assert.equal(coupleRes.body.couple.name, 'Mia & Ben');
  assert.equal(coupleRes.body.couple.anniversary, '2023-11-07');
  assert.equal(coupleRes.body.couple.members.length, 2);

  const messages = await aApi.get('/api/messages');
  assert.deepEqual(
    messages.body.messages.map((m) => m.id),
    [msg.id, voice.id],
  );

  // voice media still served from disk
  const rawVoice = await client(second.baseUrl).get(`${voice.audioUrl}?token=${a.token}`);
  assert.equal(rawVoice.status, 200);
  assert.deepEqual(rawVoice.body, Buffer.from('voice-bytes'));
});
