import { test } from 'node:test';
import assert from 'node:assert/strict';
import { access } from 'node:fs/promises';
import path from 'node:path';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('DELETE /api/couple: partner notified, tokens revoked, media wiped, sockets closed', async (t) => {
  const { baseUrl, dataDir } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const photo = (
    await a.api.post('/api/photos', { body: Buffer.from('jpeg-bytes'), headers: { 'content-type': 'image/jpeg' } })
  ).body.photo;
  const voice = (
    await b.api.post('/api/voice', { body: Buffer.from('m4a-bytes'), headers: { 'content-type': 'audio/mp4' } })
  ).body.message;
  const photoFile = path.join(dataDir, 'media', 'photos', `${photo.id}.jpg`);
  const voiceFile = path.join(dataDir, 'media', 'voice', `${voice.id}.m4a`);
  await access(photoFile);
  await access(voiceFile);

  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const res = await a.api.del('/api/couple');
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { ok: true });

  const dissolved = await bSock.waitFor('couple_dissolved');
  assert.deepEqual(dissolved.payload, {});

  // Server closes the couple's sockets after delivering the frame.
  await aSock.closed();
  await bSock.closed();

  // Both tokens are now invalid.
  for (const who of [a, b]) {
    const denied = await who.api.get('/api/couple');
    assert.equal(denied.status, 401);
    assert.equal(denied.body.error, 'invalid_token');
  }

  // Media files are gone.
  await assert.rejects(access(photoFile));
  await assert.rejects(access(voiceFile));

  // The pairing code no longer works either.
  const rejoin = await fetch(`${baseUrl}/api/couples/join`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ code: 'ABCDEF', name: 'Ghost' }),
  });
  assert.equal(rejoin.status, 404);
});

test('dissolving one couple leaves other couples untouched', async (t) => {
  const { baseUrl } = await makeApp(t);
  const doomed = await setupCouple(baseUrl);
  const survivors = await setupCouple(baseUrl);
  await doomed.a.api.del('/api/couple');
  const res = await survivors.a.api.get('/api/couple');
  assert.equal(res.status, 200);
  assert.equal(res.body.couple.members.length, 2);
});
