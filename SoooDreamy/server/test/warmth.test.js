import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen, client } from './helpers.js';

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

// === „3 gute Dinge" evening ritual =============================================================

test('goodthings: anti-spoiler reveal, streak and the once-only both-shared event', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const today = todayKey();

  const shared = await a.api.post(`/api/goodthings/${today}`, {
    json: { items: [{ text: 'Morgenkaffee auf dem Balkon' }, { text: 'Dein Lachen am Telefon', aboutPartner: true }] },
  });
  assert.equal(shared.status, 201);
  assert.equal(shared.body.mine.length, 2);
  assert.equal(shared.body.partner, null);
  assert.equal(shared.body.partnerShared, false);
  assert.equal(shared.body.bothShared, false);

  // B truthfully sees "partner shared" but cannot read the items yet.
  const bBefore = await b.api.get(`/api/goodthings/${today}`);
  assert.equal(bBefore.body.partnerShared, true);
  assert.equal(bBefore.body.partner, null, 'anti-spoiler: items hidden before sharing own');

  const wsA = await wsOpen(baseUrl, a.token, t);
  const bShared = await b.api.post(`/api/goodthings/${today}`, {
    json: { items: [{ text: 'Feierabend-Spaziergang' }] },
  });
  assert.equal(bShared.status, 201);
  assert.equal(bShared.body.bothShared, true);
  assert.equal(bShared.body.streak, 1);
  assert.deepEqual(bShared.body.partner.map((i) => i.text).sort()[1], 'Morgenkaffee auf dem Balkon');

  // A gets a tailored WS frame (their own view) plus the both-shared app event.
  const frame = await wsA.waitFor('goodthings');
  assert.equal(frame.payload.bothShared, true);
  assert.equal(frame.payload.mine.length, 2);
  const event = await wsA.waitFor('app_event', (m) => m.payload.event.type === 'goodthings_both');
  assert.equal(event.payload.event.data.dateKey, today);

  // Re-sharing replaces the list but never re-fires the event (dedupe per day).
  const again = await a.api.post(`/api/goodthings/${today}`, { json: { items: [{ text: 'Nur eins heute' }] } });
  assert.equal(again.status, 201);
  assert.equal(again.body.mine.length, 1);
  await new Promise((r) => setTimeout(r, 100));
  wsA.assertNone('app_event');
});

test('goodthings: list endpoint, mentions feed and validation limits', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const today = todayKey();

  // items must be 1–3 non-empty texts
  const none = await a.api.post(`/api/goodthings/${today}`, { json: { items: [] } });
  assert.equal(none.status, 400);
  assert.equal(none.body.error, 'bad_items');
  const four = await a.api.post(`/api/goodthings/${today}`, {
    json: { items: [{ text: '1' }, { text: '2' }, { text: '3' }, { text: '4' }] },
  });
  assert.equal(four.status, 400);

  // dateKey must be near server-today (no backfilling ancient gratitude)
  const old = await a.api.post('/api/goodthings/2020-01-01', { json: { items: [{ text: 'nope' }] } });
  assert.equal(old.status, 400);
  assert.equal(old.body.error, 'bad_datekey');

  await a.api.post(`/api/goodthings/${today}`, {
    json: { items: [{ text: 'Kochen mit dir', aboutPartner: true }, { text: 'Sonne' }] },
  });

  // Mentions stay hidden until the viewer shared that day too.
  const hidden = await b.api.get('/api/goodthings/mentions');
  assert.deepEqual(hidden.body.mentions, []);

  await b.api.post(`/api/goodthings/${today}`, { json: { items: [{ text: 'Alles' }] } });
  const mentions = await b.api.get('/api/goodthings/mentions');
  assert.equal(mentions.body.mentions.length, 1);
  assert.deepEqual(mentions.body.mentions[0], { dateKey: today, texts: ['Kochen mit dir'] });

  const list = await a.api.get('/api/goodthings?limit=5');
  assert.equal(list.body.days.length, 1);
  assert.equal(list.body.streak, 1);
});

// === Danke-Funken ==============================================================================

test('thanks: sparks land live, custom needs a note, weekly summary aggregates', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);

  const wsB = await wsOpen(baseUrl, b.token, t);
  const sent = await a.api.post('/api/thanks', { json: { category: 'cooking' } });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.spark.category, 'cooking');
  assert.equal(sent.body.spark.forMember, b.memberId);

  const frame = await wsB.waitFor('thanks');
  assert.equal(frame.payload.spark.id, sent.body.spark.id);

  const badCategory = await a.api.post('/api/thanks', { json: { category: 'bribes' } });
  assert.equal(badCategory.status, 400);
  const customNoText = await a.api.post('/api/thanks', { json: { category: 'custom' } });
  assert.equal(customNoText.status, 400);
  assert.equal(customNoText.body.error, 'bad_text');

  await a.api.post('/api/thanks', { json: { category: 'cooking' } });
  await b.api.post('/api/thanks', { json: { category: 'custom', text: 'Fürs Zuhören gestern Nacht' } });

  const summary = await a.api.get('/api/thanks/summary');
  assert.equal(summary.body.days, 7);
  assert.equal(summary.body.total, 3);
  assert.equal(summary.body.byCategory.cooking, 2);
  assert.equal(summary.body.byCategory.custom, 1);
  assert.equal(summary.body.topCategory, 'cooking');
  assert.equal(summary.body.byMember[a.memberId], 2);
  assert.equal(summary.body.byMember[b.memberId], 1);

  const list = await b.api.get('/api/thanks?limit=2');
  assert.equal(list.body.thanks.length, 2);
  assert.equal(list.body.thanks[0].text, 'Fürs Zuhören gestern Nacht');
  void coupleId;
});

test('thanks: a solo member has nobody to thank yet (409)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const anon = client(baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Solo', avatar: '🌙', color: '#888888' } });
  const solo = client(baseUrl, created.body.token);
  const res = await solo.post('/api/thanks', { json: { category: 'help' } });
  assert.equal(res.status, 409);
  assert.equal(res.body.error, 'no_partner');
});

// === „Ich vermisse dich"-Stufen =================================================================

test('missyou: three honest levels, one-tap answer only by the recipient', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const badLevel = await a.api.post('/api/missyou', { json: { level: 4 } });
  assert.equal(badLevel.status, 400);
  assert.equal(badLevel.body.error, 'bad_level');
  const floatLevel = await a.api.post('/api/missyou', { json: { level: 1.5 } });
  assert.equal(floatLevel.status, 400);

  const wsB = await wsOpen(baseUrl, b.token, t);
  const sent = await a.api.post('/api/missyou', { json: { level: 3, note: 'Langer Tag ohne dich' } });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.signal.level, 3);
  assert.equal(sent.body.signal.ackAt, null);

  const frame = await wsB.waitFor('missyou');
  assert.equal(frame.payload.signal.id, sent.body.signal.id);

  // Only the recipient may answer.
  const selfAck = await a.api.post(`/api/missyou/${sent.body.signal.id}/ack`, { json: {} });
  assert.equal(selfAck.status, 403);
  assert.equal(selfAck.body.error, 'wrong_actor');

  const ack = await b.api.post(`/api/missyou/${sent.body.signal.id}/ack`, { json: { note: 'Bin um 21 Uhr da ❤️' } });
  assert.equal(ack.status, 200);
  assert.equal(ack.body.signal.ackNote, 'Bin um 21 Uhr da ❤️');
  assert.ok(ack.body.signal.ackAt);

  const twice = await b.api.post(`/api/missyou/${sent.body.signal.id}/ack`, { json: {} });
  assert.equal(twice.status, 409);
  assert.equal(twice.body.error, 'already_acked');

  const list = await a.api.get('/api/missyou');
  assert.equal(list.body.missyou.length, 1);
  assert.equal(list.body.missyou[0].ackNote, 'Bin um 21 Uhr da ❤️');
});

// === Insider-Wörterbuch ========================================================================

test('dictionary: propose, partner co-signs, edits reset the confirmation', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const proposed = await a.api.post('/api/dictionary', {
    json: { term: 'Flauschzeit', definition: 'Sofa + Decke + wir', story: 'Seit dem Regensonntag im März', emoji: '🛋' },
  });
  assert.equal(proposed.status, 201);
  const entryId = proposed.body.entry.id;
  assert.equal(proposed.body.entry.confirmedAt, null);

  // The author cannot co-sign their own definition.
  const selfConfirm = await a.api.post(`/api/dictionary/${entryId}/confirm`);
  assert.equal(selfConfirm.status, 403);
  assert.equal(selfConfirm.body.error, 'wrong_actor');

  const confirmed = await b.api.post(`/api/dictionary/${entryId}/confirm`);
  assert.equal(confirmed.status, 200);
  assert.equal(confirmed.body.entry.confirmedBy, b.memberId);

  const twice = await b.api.post(`/api/dictionary/${entryId}/confirm`);
  assert.equal(twice.status, 409);

  // Only the author edits; editing invalidates the partner's signature.
  const partnerEdit = await b.api.patch(`/api/dictionary/${entryId}`, { json: { definition: 'Hijacked' } });
  assert.equal(partnerEdit.status, 403);
  const edited = await a.api.patch(`/api/dictionary/${entryId}`, { json: { definition: 'Sofa, Decke, wir — und Tee' } });
  assert.equal(edited.status, 200);
  assert.equal(edited.body.entry.confirmedAt, null, 'edit resets the co-sign');

  // Deleting is author-only too.
  const partnerDelete = await b.api.del(`/api/dictionary/${entryId}`);
  assert.equal(partnerDelete.status, 403);
  const deleted = await a.api.del(`/api/dictionary/${entryId}`);
  assert.equal(deleted.status, 200);
  const list = await a.api.get('/api/dictionary');
  assert.deepEqual(list.body.entries, []);
});

test('dictionary: confirming co-signs exactly one dictionary_confirmed event', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const wsA = await wsOpen(baseUrl, a.token, t);

  const proposed = await a.api.post('/api/dictionary', { json: { term: 'Brummel', definition: 'Unser Auto' } });
  await b.api.post(`/api/dictionary/${proposed.body.entry.id}/confirm`);
  const event = await wsA.waitFor('app_event', (m) => m.payload.event.type === 'dictionary_confirmed');
  assert.equal(event.payload.event.data.entryId, proposed.body.entry.id);
});

// === Erste-Male-Sammlung ========================================================================

test('firsts: timeline of firsts with photos, edits and author-only rules', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  // A first can only lie in the past.
  const future = await a.api.post('/api/firsts', { json: { title: 'Erster Marsflug', dateKey: '2999-01-01' } });
  assert.equal(future.status, 400);
  assert.equal(future.body.error, 'bad_datekey');

  const phantomPhoto = await a.api.post('/api/firsts', {
    json: { title: 'Erster Kuss', dateKey: '2023-06-14', photoId: 'ph_missing' },
  });
  assert.equal(phantomPhoto.status, 404);

  const first = await a.api.post('/api/firsts', {
    json: { title: 'Erster Kuss', emoji: '💋', dateKey: '2023-06-14', note: 'Am See, es hat geregnet' },
  });
  assert.equal(first.status, 201);
  const second = await b.api.post('/api/firsts', {
    json: { title: 'Erster gemeinsamer Urlaub', dateKey: '2024-08-02' },
  });
  assert.equal(second.status, 201);

  // Timeline is sorted by the first's date, oldest first.
  const list = await a.api.get('/api/firsts');
  assert.deepEqual(list.body.firsts.map((f) => f.title), ['Erster Kuss', 'Erster gemeinsamer Urlaub']);

  // Author-only edit/delete.
  const partnerEdit = await b.api.patch(`/api/firsts/${first.body.first.id}`, { json: { title: 'X' } });
  assert.equal(partnerEdit.status, 403);
  const edit = await a.api.patch(`/api/firsts/${first.body.first.id}`, { json: { note: null, emoji: '💞' } });
  assert.equal(edit.status, 200);
  assert.equal(edit.body.first.note, null);
  assert.equal(edit.body.first.emoji, '💞');

  const del = await b.api.del(`/api/firsts/${second.body.first.id}`);
  assert.equal(del.status, 200);
  const after = await a.api.get('/api/firsts');
  assert.equal(after.body.firsts.length, 1);
});

test('firsts: logging fires first_logged once and never again on edits', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const wsB = await wsOpen(baseUrl, b.token, t);

  const first = await a.api.post('/api/firsts', { json: { title: 'Erste gemeinsame Wohnung', dateKey: '2025-01-15' } });
  const event = await wsB.waitFor('app_event', (m) => m.payload.event.type === 'first_logged');
  assert.equal(event.payload.event.data.firstId, first.body.first.id);

  await a.api.patch(`/api/firsts/${first.body.first.id}`, { json: { title: 'Erste eigene Wohnung' } });
  await new Promise((r) => setTimeout(r, 100));
  wsB.assertNone('app_event');
});

// === Kosename (petName) ========================================================================

test('petName: set via PATCH /api/me, visible to both, clearable', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const set = await a.api.patch('/api/me', { json: { petName: 'Schnuffel' } });
  assert.equal(set.status, 200);
  assert.equal(set.body.member.petName, 'Schnuffel');

  // The partner sees it on the couple object (for "Schnuffel denkt an dich").
  const couple = await b.api.get('/api/couple');
  const mia = couple.body.couple.members.find((m) => m.id === a.memberId);
  assert.equal(mia.petName, 'Schnuffel');

  const blank = await a.api.patch('/api/me', { json: { petName: '   ' } });
  assert.equal(blank.body.member.petName, null, 'whitespace-only clears');
  const cleared = await a.api.patch('/api/me', { json: { petName: null } });
  assert.equal(cleared.body.member.petName, null);

  const tooLong = await a.api.patch('/api/me', { json: { petName: 'x'.repeat(41) } });
  assert.equal(tooLong.status, 400);
});

// === Chat send-effects ==========================================================================

test('message effects: stored, broadcast and backward-compatible null', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const plain = await a.api.post('/api/messages', { json: { type: 'text', text: 'ohne Effekt' } });
  assert.equal(plain.status, 201);
  assert.equal(plain.body.message.effect, null);

  const invalid = await a.api.post('/api/messages', { json: { type: 'text', text: 'kaboom', effect: 'lasers' } });
  assert.equal(invalid.status, 400);

  const wsB = await wsOpen(baseUrl, b.token, t);
  const sent = await a.api.post('/api/messages', {
    json: { type: 'text', text: 'Ich liebe dich!', effect: 'hearts' },
  });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.message.effect, 'hearts');
  const frame = await wsB.waitFor('message', (m) => m.payload.message.id === sent.body.message.id);
  assert.equal(frame.payload.message.effect, 'hearts');

  // Invisible ink works on letters too.
  // Use the other member: effects are deliberately rate-limited per sender.
  const letter = await b.api.post('/api/messages', {
    json: { type: 'letter', text: 'Rubbel mich frei', title: 'Psst', effect: 'invisible' },
  });
  assert.equal(letter.status, 201);
  assert.equal(letter.body.message.effect, 'invisible');

  const list = await b.api.get('/api/messages');
  const fetched = list.body.messages.find((m) => m.id === plain.body.message.id);
  assert.equal(fetched.effect, null, 'old messages default to effect null');
});
