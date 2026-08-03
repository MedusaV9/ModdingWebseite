import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { makeApp, client } from './helpers.js';

/**
 * A store.json exactly as a v1.0 server would have written it: no moodHistory,
 * wordle or coupons on the couple, no thumbUrl/favorites on photos, no
 * openWhen/reactions on messages.
 */
function v1StoreJson() {
  const at = '2024-01-02T00:00:00.000Z';
  const member = (id, name) => ({
    id,
    name,
    avatar: '💞',
    color: '#FF5C8A',
    mood: null,
    moodNote: null,
    moodUpdatedAt: null,
    lastSeenAt: null,
    joinedAt: at,
  });
  return {
    version: 1,
    couples: {
      c_old: {
        id: 'c_old',
        code: 'OLDCPL',
        name: 'Mia & Ben',
        anniversary: '2023-11-07',
        createdAt: at,
        members: [member('m_a', 'Mia'), member('m_b', 'Ben')],
        touches: [],
        messages: [
          {
            id: 'msg_old1',
            senderId: 'm_a',
            type: 'letter',
            text: 'a letter from the v1.0 days',
            title: 'old times',
            audioUrl: null,
            durationSec: null,
            createdAt: at,
          },
        ],
        photos: [
          {
            id: 'ph_old1',
            uploaderId: 'm_a',
            caption: 'v1.0 photo',
            url: '/api/photos/ph_old1/raw',
            width: 100,
            height: 100,
            createdAt: at,
          },
        ],
        events: [],
        bucket: [],
        strokes: [
          { id: 's_old1', memberId: 'm_a', color: '#FFFFFF', width: 4, tool: 'pen', points: [[0.1, 0.2]], createdAt: at },
        ],
        daily: {
          '2024-01-02': { questionId: 5, answers: { m_a: { text: 'only Mia answered', answeredAt: at } } },
        },
        games: [],
        counters: { messages: 1, gamesPlayed: 0, touches: {} },
      },
    },
    tokens: {
      tok_old_a: { coupleId: 'c_old', memberId: 'm_a' },
      tok_old_b: { coupleId: 'c_old', memberId: 'm_b' },
    },
  };
}

test('a v1.0 store.json loads cleanly and all v1.1/v1.2 endpoints work on it', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-compat-'));
  await writeFile(path.join(dataDir, 'store.json'), JSON.stringify(v1StoreJson(), null, 2), 'utf8');

  const { baseUrl } = await makeApp(t, { dataDir });
  // Registered after makeApp so the rm runs after the app's close hook (hooks are FIFO).
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const a = client(baseUrl, 'tok_old_a');
  const b = client(baseUrl, 'tok_old_b');

  // Old tokens and data still work.
  const couple = await a.get('/api/couple');
  assert.equal(couple.status, 200);
  assert.equal(couple.body.couple.id, 'c_old');
  assert.equal(couple.body.couple.members.length, 2);

  // Old messages gain openWhen: null and reactions: null on the way out.
  const messages = await a.get('/api/messages');
  assert.equal(messages.status, 200);
  assert.equal(messages.body.messages[0].id, 'msg_old1');
  assert.equal(messages.body.messages[0].openWhen, null);
  assert.equal(messages.body.messages[0].reactions, null);

  // Old photos gain thumbUrl: null and favorites: [] on the way out.
  const photos = await b.get('/api/photos');
  assert.equal(photos.status, 200);
  assert.equal(photos.body.photos[0].id, 'ph_old1');
  assert.equal(photos.body.photos[0].thumbUrl, null);
  assert.deepEqual(photos.body.photos[0].favorites, []);
  assert.equal((await a.get('/api/photos/ph_old1/thumb/raw')).body.error, 'no_thumb');

  // Thumbs can be attached to a v1.0 photo (uploader only).
  const thumbBytes = Buffer.from('compat-thumb');
  const denied = await b.post('/api/photos/ph_old1/thumb', { body: thumbBytes, headers: { 'content-type': 'image/jpeg' } });
  assert.equal(denied.status, 403);
  const thumb = await a.post('/api/photos/ph_old1/thumb', { body: thumbBytes, headers: { 'content-type': 'image/jpeg' } });
  assert.equal(thumb.status, 200);
  assert.equal(thumb.body.photo.thumbUrl, '/api/photos/ph_old1/thumb/raw');
  const raw = await b.get('/api/photos/ph_old1/thumb/raw');
  assert.equal(raw.status, 200);
  assert.deepEqual(raw.body, thumbBytes);

  // Mood history starts empty (missing structure is defaulted) and accumulates.
  assert.deepEqual((await a.get('/api/moods')).body, { moods: [] });
  await a.patch('/api/me', { json: { mood: '🥹', moodNote: 'nostalgia' } });
  const moods = (await b.get('/api/moods')).body.moods;
  assert.equal(moods.length, 1);
  assert.equal(moods[0].memberId, 'm_a');
  assert.equal(moods[0].mood, '🥹');
  assert.equal(moods[0].moodNote, 'nostalgia');

  // Daily journal list works on the old daily record with per-member reveal.
  const aDaily = (await a.get('/api/daily')).body.entries;
  assert.equal(aDaily.length, 1);
  assert.equal(aDaily[0].dateKey, '2024-01-02');
  assert.equal(aDaily[0].myAnswer, 'only Mia answered');
  assert.equal(aDaily[0].partnerAnswer, null);
  const bDaily = (await b.get('/api/daily')).body.entries;
  assert.equal(bDaily[0].myAnswer, null);
  assert.equal(bDaily[0].partnerAnswer, null);

  // Stroke delete honors authorship on old strokes.
  assert.equal((await b.del('/api/canvas/strokes/s_old1')).status, 403);
  assert.equal((await a.del('/api/canvas/strokes/s_old1')).status, 200);
  assert.equal((await a.get('/api/canvas')).body.strokes.length, 0);

  // Sealed letters work on the old couple too.
  const letter = await b.post('/api/messages', { json: { type: 'letter', text: 'new sealed', openWhen: 'someday' } });
  assert.equal(letter.status, 201);
  assert.equal(letter.body.message.openWhen, 'someday');

  // --- v1.2 features on the old store ---

  // Reactions toggle on the v1.0 message (no reactions key stored).
  const reacted = await b.post('/api/messages/msg_old1/reactions', { json: { emoji: '💌' } });
  assert.equal(reacted.status, 200);
  assert.deepEqual(reacted.body.message.reactions, { '💌': ['m_b'] });

  // Wordle duel (couple.wordle is defaulted lazily) with anti-spoiler view.
  const wordle = await a.post('/api/wordle/2026-08-03', { json: { rows: 4, win: true, grid: '🟩', lang: 'de' } });
  assert.equal(wordle.status, 200);
  assert.equal(wordle.body.mine.rows, 4);
  const bWordle = await b.get('/api/wordle/2026-08-03');
  assert.equal(bWordle.body.partner, null);
  assert.equal(bWordle.body.partnerFinished, true);

  // Favorite the v1.0 photo (no favorites key stored).
  const fav = await b.post('/api/photos/ph_old1/favorite');
  assert.equal(fav.status, 200);
  assert.deepEqual(fav.body.photo.favorites, ['m_b']);

  // Coupons (couple.coupons is defaulted lazily): create, redeem by the partner.
  const coupon = await a.post('/api/coupons', { json: { title: 'Retro dinner', emoji: '🍝' } });
  assert.equal(coupon.status, 201);
  assert.equal(coupon.body.coupon.forMember, 'm_b');
  const redeemed = await b.post(`/api/coupons/${coupon.body.coupon.id}/redeem`);
  assert.equal(redeemed.status, 200);
  assert.ok(redeemed.body.coupon.redeemedAt);
});
