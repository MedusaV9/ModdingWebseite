import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('couple palette, monogram style, and pet names sync to both members', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const socket = await wsOpen(baseUrl, b.token, t);
  await socket.waitFor('welcome');

  const me = await a.api.patch('/api/me', { json: { petName: 'Sternchen' } });
  assert.equal(me.status, 200);
  assert.equal(me.body.member.petName, 'Sternchen');
  const memberFrame = await socket.waitFor('member_updated');
  assert.equal(memberFrame.payload.member.petName, 'Sternchen');

  const palette = {
    primary: '#60A5FA',
    secondary: '#6EE7B7',
    accent: '#FFFFFF',
    onAccent: '#09040D',
  };
  const updated = await a.api.patch('/api/couple', {
    json: { palette, monogramStyle: 'ribbon' },
  });
  assert.equal(updated.status, 200);
  assert.deepEqual(updated.body.couple.palette, palette);
  assert.equal(updated.body.couple.monogramStyle, 'ribbon');
  const coupleFrame = await socket.waitFor('couple_updated');
  assert.deepEqual(coupleFrame.payload.couple.palette, palette);

  const lowContrast = await b.api.patch('/api/couple', {
    json: {
      palette: {
        primary: '#FFFFFF',
        secondary: '#FFFFFF',
        accent: '#221133',
        onAccent: '#FFFFFF',
      },
    },
  });
  assert.equal(lowContrast.status, 400);
  assert.equal(lowContrast.body.error, 'low_contrast');
});

test('procedural stickers and send effects validate, persist, and broadcast', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const socket = await wsOpen(baseUrl, b.token, t);
  await socket.waitFor('welcome');

  const recipe = { shape: 'seal', color: '#FF5C8A', seed: 4242, label: 'Für dich' };
  const sent = await a.api.post('/api/messages', {
    json: { type: 'sticker', sticker: recipe, effect: 'sparkle' },
  });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.message.type, 'sticker');
  assert.deepEqual(sent.body.message.sticker, recipe);
  assert.equal(sent.body.message.effect, 'sparkle');
  const frame = await socket.waitFor('message');
  assert.deepEqual(frame.payload.message.sticker, recipe);

  const list = await b.api.get('/api/messages');
  assert.deepEqual(list.body.messages[0].sticker, recipe);

  const rateLimited = await a.api.post('/api/messages', {
    json: { type: 'text', text: 'too soon', effect: 'hearts' },
  });
  assert.equal(rateLimited.status, 429);
  assert.equal(rateLimited.body.error, 'effect_cooldown');

  const badShape = await a.api.post('/api/messages', {
    json: { type: 'sticker', sticker: { ...recipe, shape: 'photo-cutout' } },
  });
  assert.equal(badShape.status, 400);
  const badEffect = await a.api.post('/api/messages', {
    json: { type: 'text', text: 'hi', effect: 'unbounded-confetti' },
  });
  assert.equal(badEffect.status, 400);
});
