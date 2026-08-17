import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { makeApp, setupCouple, wsOpen, client, dateKeyDaysAgo } from './helpers.js';

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function thisMonth() {
  return todayKey().slice(0, 7);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// === audio check-in "Wie war dein Tag?" ========================================================

test('daymemos: upload keeps the partner memo hidden until I record mine (reveal semantics)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const today = todayKey();

  const up = await a.api.post(`/api/daymemos/${today}`, {
    body: Buffer.from('aac-audio-a'),
    headers: { 'content-type': 'audio/mp4', 'x-duration-sec': '42.5' },
  });
  assert.equal(up.status, 201);
  assert.match(up.body.mine.id, /^dm_/);
  assert.equal(up.body.mine.durationSec, 42.5);
  assert.equal(up.body.partner, null);
  assert.equal(up.body.partnerRecorded, false);
  assert.equal(up.body.bothRecorded, false);

  // Partner truthfully sees "recorded", but the memo itself stays hidden.
  const bView = await b.api.get(`/api/daymemos/${today}`);
  assert.equal(bView.body.partnerRecorded, true);
  assert.equal(bView.body.partner, null, 'anti-spoiler: no memo object before recording own');

  // ...and the raw stream is refused too.
  const sneak = await b.api.get(`/api/daymemos/${up.body.mine.id}/raw`);
  assert.equal(sneak.status, 403);
  assert.equal(sneak.body.error, 'not_revealed');

  // Once B records, both sides hear both memos and the day counts for the streak.
  const upB = await b.api.post(`/api/daymemos/${today}`, {
    body: Buffer.from('aac-audio-b'),
    headers: { 'content-type': 'audio/mp4' },
  });
  assert.equal(upB.status, 201);
  assert.equal(upB.body.bothRecorded, true);
  assert.equal(upB.body.streak, 1);
  assert.equal(upB.body.partner.id, up.body.mine.id);

  const raw = await b.api.get(`/api/daymemos/${up.body.mine.id}/raw`);
  assert.equal(raw.status, 200);
  assert.equal(raw.body.toString(), 'aac-audio-a');
});

test('daymemos: WS frames are tailored per member and milestone app events fire once', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const today = todayKey();
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  await a.api.post(`/api/daymemos/${today}`, { body: Buffer.from('a1'), headers: {} });
  const toB = await bSock.waitFor('daymemo');
  assert.equal(toB.payload.partnerRecorded, true);
  assert.equal(toB.payload.partner, null, 'B has not recorded yet — no spoiler over WS either');
  const firstEvent = await aSock.waitFor('app_event', (m) => m.payload.event.type === 'daymemo_first');
  assert.equal(firstEvent.payload.event.data.dateKey, today);

  await b.api.post(`/api/daymemos/${today}`, { body: Buffer.from('b1'), headers: {} });
  const reveal = await aSock.waitFor('daymemo', (m) => m.payload.bothRecorded);
  assert.ok(reveal.payload.partner, 'A gets the partner memo once both recorded');
  const bothEvent = await bSock.waitFor('app_event', (m) => m.payload.event.type === 'daymemo_both');
  assert.equal(bothEvent.payload.event.memberId, null);
  await aSock.waitFor('app_event', (m) => m.payload.event.type === 'daymemo_both');

  // Second upload day: no daymemo_first again.
  const yesterday = dateKeyDaysAgo(1);
  await a.api.post(`/api/daymemos/${yesterday}`, { body: Buffer.from('a2'), headers: {} });
  await aSock.assertNone('app_event');
});

test('daymemos: re-recording replaces my memo and its audio file', async (t) => {
  const ctx = await makeApp(t);
  const { a } = await setupCouple(ctx.baseUrl);
  const today = todayKey();

  const first = await a.api.post(`/api/daymemos/${today}`, { body: Buffer.from('take one'), headers: {} });
  const firstId = first.body.mine.id;
  const firstFile = path.join(ctx.dataDir, 'media', 'voice', `${firstId}.m4a`);
  assert.ok(existsSync(firstFile));

  const second = await a.api.post(`/api/daymemos/${today}`, { body: Buffer.from('take two'), headers: {} });
  assert.notEqual(second.body.mine.id, firstId);
  assert.ok(!existsSync(firstFile), 'replaced audio file is deleted');

  const raw = await a.api.get(`/api/daymemos/${second.body.mine.id}/raw`);
  assert.equal(raw.body.toString(), 'take two');
});

test('daymemos: list is newest-first with limit; far-away dates and empty bodies → 400', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  await a.api.post(`/api/daymemos/${dateKeyDaysAgo(1)}`, { body: Buffer.from('y'), headers: {} });
  await b.api.post(`/api/daymemos/${dateKeyDaysAgo(1)}`, { body: Buffer.from('y2'), headers: {} });
  await a.api.post(`/api/daymemos/${todayKey()}`, { body: Buffer.from('t'), headers: {} });

  const list = await a.api.get('/api/daymemos?limit=1');
  assert.equal(list.body.days.length, 1);
  assert.equal(list.body.days[0].dateKey, todayKey());
  assert.equal((await a.api.get('/api/daymemos')).body.days.length, 2);

  const farAway = await a.api.post(`/api/daymemos/${dateKeyDaysAgo(5)}`, { body: Buffer.from('x'), headers: {} });
  assert.equal(farAway.status, 400);
  assert.equal(farAway.body.error, 'bad_datekey');
  const empty = await a.api.post(`/api/daymemos/${todayKey()}`, { body: Buffer.alloc(0), headers: {} });
  assert.equal(empty.status, 400);
  assert.equal(empty.body.error, 'empty_body');
});

// === time capsules =============================================================================

test('capsules: the server withholds text/photo from the recipient until opened', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const photo = (
    await a.api.post('/api/photos', { body: Buffer.from('jpeg'), headers: { 'content-type': 'image/jpeg' } })
  ).body.photo;

  const unlockAt = new Date(Date.now() + 60_000).toISOString();
  const sealed = await a.api.post('/api/capsules', {
    json: { title: 'Für dich', emoji: '💌', text: 'Ich liebe dich seit Tag 1', photoId: photo.id, unlockAt },
  });
  assert.equal(sealed.status, 201);
  assert.equal(sealed.body.capsule.text, 'Ich liebe dich seit Tag 1', 'creator always sees their own words');

  const bList = (await b.api.get('/api/capsules')).body.capsules;
  assert.equal(bList.length, 1);
  assert.equal(bList[0].text, null, 'recipient sees no text before opening');
  assert.equal(bList[0].photoId, null);
  assert.equal(bList[0].unlocked, false);
  assert.equal(bList[0].title, 'Für dich', 'title/emoji are the visible envelope');

  // Locked + wrong member guards.
  const early = await b.api.post(`/api/capsules/${bList[0].id}/open`);
  assert.equal(early.status, 409);
  assert.equal(early.body.error, 'still_locked');
  const notMine = await a.api.post(`/api/capsules/${bList[0].id}/open`);
  assert.equal(notMine.status, 403);
});

test('capsules: opening after unlockAt reveals content, broadcasts and emits app events', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const sealed = await b.api.post('/api/capsules', {
    json: { text: 'Überraschung!', unlockAt: new Date(Date.now() + 150).toISOString() },
  });
  assert.equal(sealed.status, 201);
  const capId = sealed.body.capsule.id;
  const sealedFrame = await aSock.waitFor('capsule_sealed');
  assert.equal(sealedFrame.payload.capsule.text, null, 'recipient WS frame is redacted too');

  await sleep(300);
  const opened = await a.api.post(`/api/capsules/${capId}/open`);
  assert.equal(opened.status, 200);
  assert.equal(opened.body.capsule.text, 'Überraschung!');
  assert.ok(opened.body.capsule.openedAt);

  const openFrame = await aSock.waitFor('capsule_opened');
  assert.equal(openFrame.payload.capsule.text, 'Überraschung!');

  const again = await a.api.post(`/api/capsules/${capId}/open`);
  assert.equal(again.status, 409);
  assert.equal(again.body.error, 'already_opened');

  const events = (await a.api.get('/api/app-events')).body.events.map((e) => e.type);
  assert.ok(events.includes('capsule_sealed'));
  assert.ok(events.includes('capsule_opened'));
});

test('capsules: validation — past unlockAt, unknown photo, no partner, delete rules', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const past = await a.api.post('/api/capsules', {
    json: { text: 'x', unlockAt: new Date(Date.now() - 1000).toISOString() },
  });
  assert.equal(past.status, 400);
  assert.equal(past.body.error, 'bad_unlock');

  const badPhoto = await a.api.post('/api/capsules', {
    json: { text: 'x', photoId: 'ph_nope', unlockAt: new Date(Date.now() + 60_000).toISOString() },
  });
  assert.equal(badPhoto.status, 404);
  assert.equal(badPhoto.body.error, 'unknown_photo');

  // A fresh single-member couple cannot seal capsules yet.
  const anon = client(baseUrl);
  const solo = await anon.post('/api/couples', { json: { name: 'Solo' } });
  const soloApi = client(baseUrl, solo.body.token);
  const noPartner = await soloApi.post('/api/capsules', {
    json: { text: 'x', unlockAt: new Date(Date.now() + 60_000).toISOString() },
  });
  assert.equal(noPartner.status, 409);
  assert.equal(noPartner.body.error, 'no_partner');

  // Only the creator may delete — and only while unopened.
  const sealed = await a.api.post('/api/capsules', {
    json: { text: 'weg damit', unlockAt: new Date(Date.now() + 60_000).toISOString() },
  });
  const capId = sealed.body.capsule.id;
  assert.equal((await b.api.del(`/api/capsules/${capId}`)).status, 403);
  assert.equal((await a.api.del(`/api/capsules/${capId}`)).status, 200);
  assert.equal((await a.api.get('/api/capsules')).body.capsules.length, 0);
});

test('capsules: the archive cap evicts oldest OPENED capsules before sealed ones', async (t) => {
  const ctx = await makeApp(t);
  const { a, b } = await setupCouple(ctx.baseUrl);
  const bSock = await wsOpen(ctx.baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  // Fill the archive to the cap of 100 directly in the store (fast path);
  // capsule #0 is opened, all others still sealed.
  const couple = Object.values(ctx.app.store.data.couples)[0];
  couple.capsules = Array.from({ length: 100 }, (_, i) => ({
    id: `cap_seed${i}`,
    title: `Nr. ${i}`,
    emoji: null,
    text: 'alt',
    photoId: null,
    unlockAt: new Date(Date.now() + 3600_000).toISOString(),
    createdBy: a.memberId,
    forMember: b.memberId,
    createdAt: new Date(Date.now() - (200 - i) * 60_000).toISOString(),
    openedAt: i === 0 ? new Date().toISOString() : null,
  }));

  const sealed = await a.api.post('/api/capsules', {
    json: { text: 'die 101.', unlockAt: new Date(Date.now() + 3600_000).toISOString() },
  });
  assert.equal(sealed.status, 201);
  const gone = await bSock.waitFor('capsule_deleted');
  assert.equal(gone.payload.id, 'cap_seed0', 'the opened capsule is evicted, not a sealed one');

  const list = (await a.api.get('/api/capsules')).body.capsules;
  assert.equal(list.length, 100);
  assert.ok(!list.some((cap) => cap.id === 'cap_seed0'));
  assert.ok(list.some((cap) => cap.id === sealed.body.capsule.id));
});

// === need button ===============================================================================

test('needs: one tap reaches the partner live, ack flows back, history is newest-first', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const sent = await a.api.post('/api/needs', { json: { type: 'closeness', note: 'Kuscheln?' } });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.need.forMember, b.memberId);
  assert.equal(sent.body.need.ackAt, null);

  const frame = await bSock.waitFor('need');
  assert.equal(frame.payload.need.type, 'closeness');
  const appEvent = await bSock.waitFor('app_event', (m) => m.payload.event.type === 'need_sent');
  assert.equal(appEvent.payload.event.data.needType, 'closeness');

  // Sender cannot ack their own need; the partner can, exactly once.
  const needId = sent.body.need.id;
  assert.equal((await a.api.post(`/api/needs/${needId}/ack`)).status, 403);
  const acked = await b.api.post(`/api/needs/${needId}/ack`, { json: { note: 'Bin da 🤍' } });
  assert.equal(acked.status, 200);
  assert.equal(acked.body.need.ackNote, 'Bin da 🤍');
  assert.equal((await b.api.post(`/api/needs/${needId}/ack`)).status, 409);

  await a.api.post('/api/needs', { json: { type: 'space' } });
  const history = (await a.api.get('/api/needs')).body.needs;
  assert.equal(history.length, 2);
  assert.equal(history[0].type, 'space', 'newest first');
  assert.equal((await a.api.get('/api/needs?limit=1')).body.needs.length, 1);

  const bad = await a.api.post('/api/needs', { json: { type: 'coffee' } });
  assert.equal(bad.status, 400);
});

test('needs: inbox digest counts new signals for me and surfaces the open one', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const since = new Date(Date.now() - 1000).toISOString();

  await a.api.post('/api/needs', { json: { type: 'listen' } });
  const second = (await a.api.post('/api/needs', { json: { type: 'comfort' } })).body.need;

  const bInbox = (await b.api.get(`/api/inbox?since=${encodeURIComponent(since)}`)).body;
  assert.equal(bInbox.needsForMe.count, 2);
  assert.equal(bInbox.needsForMe.openNeed.id, second.id, 'newest unanswered need is the teaser');

  // The sender's own inbox is unaffected...
  const aInbox = (await a.api.get(`/api/inbox?since=${encodeURIComponent(since)}`)).body;
  assert.equal(aInbox.needsForMe.count, 0);
  assert.equal(aInbox.needsForMe.openNeed, null);

  // ...and acking clears the teaser (counts stay historical).
  await b.api.post(`/api/needs/${second.id}/ack`);
  const after = (await b.api.get(`/api/inbox?since=${encodeURIComponent(since)}`)).body;
  assert.equal(after.needsForMe.count, 2);
  assert.ok(after.needsForMe.openNeed, 'the older need is still open');
  assert.notEqual(after.needsForMe.openNeed.id, second.id);
});

test('needs: without a partner the button politely refuses', async (t) => {
  const { baseUrl } = await makeApp(t);
  const anon = client(baseUrl);
  const solo = await anon.post('/api/couples', { json: { name: 'Solo' } });
  const api = client(baseUrl, solo.body.token);

  const refused = await api.post('/api/needs', { json: { type: 'space' } });
  assert.equal(refused.status, 409);
  assert.equal(refused.body.error, 'no_partner');
  assert.deepEqual((await api.get('/api/needs')).body.needs, []);
});

// === shared goals ==============================================================================

test('goals: create, book progress from both sides, live totals and percent', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const created = await a.api.post('/api/goals', {
    json: { title: 'Japan-Reise', emoji: '🗾', targetValue: 3000, unit: '€', targetDate: '2027-05-01' },
  });
  assert.equal(created.status, 201);
  const goalId = created.body.goal.id;
  assert.equal(created.body.goal.percent, 0);
  await bSock.waitFor('goal_added');

  const c1 = await a.api.post(`/api/goals/${goalId}/contributions`, { json: { amount: 300, note: 'Bonus' } });
  assert.equal(c1.status, 201);
  assert.equal(c1.body.goal.total, 300);
  assert.equal(c1.body.goal.percent, 10);
  assert.equal(c1.body.milestone, null);

  const c2 = await b.api.post(`/api/goals/${goalId}/contributions`, { json: { amount: 450.5 } });
  assert.equal(c2.body.goal.total, 750.5);
  assert.equal(c2.body.milestone, 25, '25 % crossing rides along for confetti');
  const frame = await bSock.waitFor('goal_updated', (m) => m.payload.milestone === 25);
  assert.equal(frame.payload.goal.total, 750.5);

  assert.equal((await a.api.post('/api/goals', { json: { title: 'x', targetValue: 0 } })).status, 400);
  assert.equal((await a.api.post(`/api/goals/${goalId}/contributions`, { json: { amount: 0 } })).status, 400);
  assert.equal((await a.api.post('/api/goals/gl_nope/contributions', { json: { amount: 5 } })).status, 404);
});

test('goals: reaching 100 % completes the goal, emits milestones, corrections re-open it', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const goalId = (await a.api.post('/api/goals', { json: { title: '10 Dates', targetValue: 10 } })).body.goal.id;
  const jump = await b.api.post(`/api/goals/${goalId}/contributions`, { json: { amount: 10 } });
  assert.equal(jump.body.milestone, 100, 'the last crossed milestone wins the broadcast');
  assert.ok(jump.body.goal.completedAt);

  // One jump over 25/50/75/100 emits each app-event milestone exactly once.
  const events = (await a.api.get('/api/app-events')).body.events;
  const milestones = events.filter((e) => e.type === 'goal_milestone').map((e) => e.data.percent);
  assert.deepEqual(milestones.sort((x, y) => x - y), [25, 50, 75]);
  assert.equal(events.filter((e) => e.type === 'goal_reached').length, 1);
  assert.ok(events.some((e) => e.type === 'goal_created'));

  // A negative correction drops below 100 % and re-opens the goal.
  const fix = await a.api.post(`/api/goals/${goalId}/contributions`, { json: { amount: -2 } });
  assert.equal(fix.body.goal.completedAt, null);
  assert.equal(fix.body.goal.percent, 80);

  // Both partners may edit and delete — it is a joint project.
  const patched = await b.api.patch(`/api/goals/${goalId}`, { json: { targetValue: 8 } });
  assert.ok(patched.body.goal.completedAt, 'lowering the target can complete the goal');
  assert.equal((await b.api.del(`/api/goals/${goalId}`)).status, 200);
  assert.equal((await a.api.get('/api/goals')).body.goals.length, 0);
});

test('goals: widget snapshot exposes the most recently active open goal for Agent C', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  assert.equal((await a.api.get('/api/widget-snapshot')).body.goal, null);

  const g1 = (await a.api.post('/api/goals', { json: { title: 'Erstes', targetValue: 100 } })).body.goal;
  const g2 = (await a.api.post('/api/goals', { json: { title: 'Zweites', emoji: '🏝️', targetValue: 50 } })).body.goal;
  assert.equal((await b.api.get('/api/widget-snapshot')).body.goal.id, g2.id, 'newest activity wins');

  await b.api.post(`/api/goals/${g1.id}/contributions`, { json: { amount: 40 } });
  const snap = (await a.api.get('/api/widget-snapshot')).body.goal;
  assert.equal(snap.id, g1.id, 'a contribution makes the goal the active one');
  assert.equal(snap.percent, 40);
  assert.equal(snap.title, 'Erstes');

  // Completed goals leave the widget.
  await b.api.post(`/api/goals/${g1.id}/contributions`, { json: { amount: 60 } });
  assert.equal((await a.api.get('/api/widget-snapshot')).body.goal.id, g2.id);
});

test('goals: the couple cap of 50 goals returns 413 with a friendly nudge', async (t) => {
  const ctx = await makeApp(t);
  const { a } = await setupCouple(ctx.baseUrl);

  const couple = Object.values(ctx.app.store.data.couples)[0];
  couple.goals = Array.from({ length: 50 }, (_, i) => ({
    id: `gl_seed${i}`,
    title: `Ziel ${i}`,
    emoji: null,
    targetValue: 10,
    unit: null,
    targetDate: null,
    createdBy: a.memberId,
    createdAt: new Date().toISOString(),
    completedAt: null,
    contributions: [],
  }));

  const refused = await a.api.post('/api/goals', { json: { title: 'eins zu viel', targetValue: 1 } });
  assert.equal(refused.status, 413);
  assert.equal(refused.body.error, 'too_many_goals');
  assert.equal((await a.api.get('/api/goals')).body.goals.length, 50);
});

// === week plan =================================================================================

test('weekplan: availability per member, overlap sparkles only when both are non-busy', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');
  const day = dateKeyDaysAgo(-2); // the day after tomorrow

  const setA = await a.api.put(`/api/weekplan/${day}/availability`, { json: { status: 'free' } });
  assert.equal(setA.status, 200);
  assert.equal(setA.body.day.overlap, false, 'one member alone is no overlap');
  const frame = await bSock.waitFor('weekplan_availability');
  assert.equal(frame.payload.memberId, a.memberId);
  assert.equal(frame.payload.status, 'free');

  const setB = await b.api.put(`/api/weekplan/${day}/availability`, { json: { status: 'date' } });
  assert.equal(setB.body.day.overlap, true);

  const busy = await b.api.put(`/api/weekplan/${day}/availability`, { json: { status: 'busy' } });
  assert.equal(busy.body.day.overlap, false, 'busy kills the overlap');

  // Clearing removes my mark entirely.
  const cleared = await a.api.put(`/api/weekplan/${day}/availability`, { json: { status: null } });
  assert.equal(cleared.body.day.availability[a.memberId], undefined);

  assert.equal((await a.api.put(`/api/weekplan/${day}/availability`, { json: { status: 'sleepy' } })).status, 400);
  const outside = await a.api.put(`/api/weekplan/${dateKeyDaysAgo(10)}/availability`, { json: { status: 'free' } });
  assert.equal(outside.status, 400);
  assert.equal(outside.body.error, 'bad_datekey');
});

test('weekplan: one-off and recurring slots appear on the right days of the board', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');
  const tomorrow = dateKeyDaysAgo(-1);
  const tomorrowWeekday = new Date(`${tomorrow}T00:00:00.000Z`).getUTCDay();

  const oneOff = await a.api.post('/api/weekplan/slots', {
    json: { title: 'Kino', emoji: '🎬', kind: 'date', dateKey: tomorrow, time: '20:00' },
  });
  assert.equal(oneOff.status, 201);
  await bSock.waitFor('weekplan_slot_added');
  const appEvent = await bSock.waitFor('app_event', (m) => m.payload.event.type === 'weekplan_slot_created');
  assert.equal(appEvent.payload.event.data.kind, 'date');

  const recurring = await b.api.post('/api/weekplan/slots', {
    json: { title: 'Telefon-Date', kind: 'call', weekday: tomorrowWeekday, time: '21:30' },
  });
  assert.equal(recurring.status, 201);

  // Board: tomorrow carries both, and the recurring slot repeats a week later.
  const board = (await a.api.get(`/api/weekplan?start=${tomorrow}&days=8`)).body;
  assert.equal(board.days[0].slots.length, 2);
  assert.deepEqual(
    board.days[0].slots.map((s) => s.title).sort(),
    ['Kino', 'Telefon-Date'],
  );
  assert.deepEqual(board.days[7].slots.map((s) => s.title), ['Telefon-Date']);
  assert.equal(board.days[1].slots.length, 0);

  // Validation: exactly one of dateKey/weekday, sane time and weekday.
  assert.equal((await a.api.post('/api/weekplan/slots', { json: { title: 'x' } })).status, 400);
  assert.equal(
    (await a.api.post('/api/weekplan/slots', { json: { title: 'x', dateKey: tomorrow, weekday: 2 } })).status,
    400,
  );
  assert.equal((await a.api.post('/api/weekplan/slots', { json: { title: 'x', weekday: 7 } })).status, 400);
  assert.equal(
    (await a.api.post('/api/weekplan/slots', { json: { title: 'x', dateKey: tomorrow, time: '24:99' } })).status,
    400,
  );
});

test('weekplan: both partners may edit slots; switching one-off ↔ recurring keeps the invariant', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const tomorrow = dateKeyDaysAgo(-1);

  const slot = (
    await a.api.post('/api/weekplan/slots', { json: { title: 'Spaziergang', dateKey: tomorrow } })
  ).body.slot;

  const patched = await b.api.patch(`/api/weekplan/slots/${slot.id}`, {
    json: { title: 'Abendspaziergang', weekday: 3, time: '19:00' },
  });
  assert.equal(patched.status, 200);
  assert.equal(patched.body.slot.title, 'Abendspaziergang');
  assert.equal(patched.body.slot.weekday, 3);
  assert.equal(patched.body.slot.dateKey, null, 'recurring now — the one-off date is gone');

  assert.equal((await b.api.del(`/api/weekplan/slots/${slot.id}`)).status, 200);
  assert.equal((await a.api.get('/api/weekplan')).body.slots.length, 0);
  assert.equal((await a.api.del('/api/weekplan/slots/ws_nope')).status, 404);
});

// === energy traffic light ======================================================================

test('energy: the light shows up on the member, in the widget snapshot, and expires after 12 h', async (t) => {
  const ctx = await makeApp(t);
  const { a, b } = await setupCouple(ctx.baseUrl);
  const bSock = await wsOpen(ctx.baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const set = await a.api.put('/api/energy', { json: { level: 'yellow', note: 'Langer Tag' } });
  assert.equal(set.status, 200);
  assert.equal(set.body.energy.level, 'yellow');
  const frame = await bSock.waitFor('energy');
  assert.equal(frame.payload.memberId, a.memberId);
  assert.equal(frame.payload.energy.note, 'Langer Tag');

  const couple = (await b.api.get('/api/couple')).body.couple;
  const partnerA = couple.members.find((m) => m.id === a.memberId);
  assert.equal(partnerA.energy.level, 'yellow');
  assert.equal((await b.api.get('/api/widget-snapshot')).body.partner.energy.level, 'yellow');

  // 13 hours later the light is stale and hidden everywhere.
  const stored = Object.values(ctx.app.store.data.couples)[0].members.find((m) => m.id === a.memberId);
  stored.energy.setAt = new Date(Date.now() - 13 * 3600_000).toISOString();
  const later = (await b.api.get('/api/couple')).body.couple.members.find((m) => m.id === a.memberId);
  assert.equal(later.energy, null);
  assert.equal((await b.api.get('/api/widget-snapshot')).body.partner.energy, null);

  assert.equal((await a.api.put('/api/energy', { json: { level: 'purple' } })).status, 400);
});

test('energy: clearing the light broadcasts null to the partner', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  await a.api.put('/api/energy', { json: { level: 'red' } });
  await bSock.waitFor('energy', (m) => m.payload.energy?.level === 'red');

  assert.equal((await a.api.del('/api/energy')).status, 200);
  const cleared = await bSock.waitFor('energy', (m) => m.payload.energy === null);
  assert.equal(cleared.payload.memberId, a.memberId);
  const couple = (await b.api.get('/api/couple')).body.couple;
  assert.equal(couple.members.find((m) => m.id === a.memberId).energy, null);
});

// === monthly magazine ==========================================================================

test('magazine: aggregates the month into photos, quote, song and stats', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const month = thisMonth();
  const today = todayKey();

  // Content: 2 photos (one favorited), messages, a both-answered daily, a song.
  const p1 = (await a.api.post('/api/photos', { body: Buffer.from('p1'), headers: {} })).body.photo;
  await b.api.post('/api/photos', { body: Buffer.from('p2'), headers: {} });
  await b.api.post(`/api/photos/${p1.id}/favorite`);
  await a.api.post('/api/messages', { json: { type: 'text', text: 'Hallo du' } });
  await b.api.post('/api/messages', { json: { type: 'text', text: 'Hallo zurück' } });
  await a.api.post(`/api/daily/${today}`, { json: { questionId: 1, text: 'Dein Lachen heute Morgen' } });
  await b.api.post(`/api/daily/${today}`, { json: { questionId: 1, text: 'Unser Abendessen' } });
  await a.api.post('/api/songs', { json: { title: 'Unser Lied', artist: 'Wir' } });
  await a.api.post(`/api/daymemos/${today}`, { body: Buffer.from('memo'), headers: {} });

  const mag = (await a.api.get(`/api/magazine/${month}`)).body;
  assert.equal(mag.month, month);
  assert.equal(mag.photos.length, 2);
  assert.equal(mag.photos[0].id, p1.id, 'favorited photo leads the spread');
  assert.equal(mag.quote.answers[a.memberId], 'Dein Lachen heute Morgen');
  assert.equal(mag.song.title, 'Unser Lied');
  assert.equal(mag.stats.messages, 2);
  assert.equal(mag.stats.photosAdded, 2);
  assert.equal(mag.stats.dailyBothAnswered, 1);
  assert.equal(mag.stats.daymemoDays, 1);
  assert.deepEqual(mag.seen, {});

  const months = (await a.api.get('/api/magazine/months')).body.months;
  assert.ok(months.includes(month));

  assert.equal((await a.api.get('/api/magazine/2099-01')).status, 400, 'no peeking into the future');
  assert.equal((await a.api.get('/api/magazine/13-2024')).status, 400);
});

test('magazine: seen receipts sync live and both-read emits one app event', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const month = thisMonth();
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const first = await b.api.post(`/api/magazine/${month}/seen`);
  assert.equal(first.status, 200);
  assert.ok(first.body.seen[b.memberId]);
  const frame = await aSock.waitFor('magazine_seen');
  assert.equal(frame.payload.memberId, b.memberId);
  await aSock.assertNone('app_event');

  // Re-marking is idempotent: no new frame, timestamp unchanged.
  const again = await b.api.post(`/api/magazine/${month}/seen`);
  assert.equal(again.body.seen[b.memberId], first.body.seen[b.memberId]);
  await aSock.assertNone('magazine_seen');

  await a.api.post(`/api/magazine/${month}/seen`);
  const bothEvent = await aSock.waitFor('app_event', (m) => m.payload.event.type === 'magazine_seen_both');
  assert.equal(bothEvent.payload.event.data.month, month);

  const mag = (await a.api.get(`/api/magazine/${month}`)).body;
  assert.equal(Object.keys(mag.seen).length, 2);
});

// === app events (milestone feed for Agent C) ===================================================

test('app-events: newest-first feed with type filter and limit', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  await a.api.post('/api/needs', { json: { type: 'space' } });
  await b.api.post('/api/goals', { json: { title: 'Ziel', targetValue: 5 } });
  await a.api.post('/api/needs', { json: { type: 'listen' } });

  const all = (await a.api.get('/api/app-events')).body.events;
  assert.equal(all.length, 3);
  assert.equal(all[0].type, 'need_sent', 'newest first');
  assert.equal(all[0].data.needType, 'listen');
  assert.equal(all[2].type, 'need_sent');
  assert.ok(all.every((e) => /^ae_/.test(e.id) && e.createdAt));

  const filtered = (await b.api.get('/api/app-events?type=goal_created')).body.events;
  assert.equal(filtered.length, 1);
  assert.equal(filtered[0].memberId, b.memberId);

  assert.equal((await a.api.get('/api/app-events?limit=1')).body.events.length, 1);
});

// === lifecycle =================================================================================

test('dissolve: deleting the couple removes day-memo audio files from disk', async (t) => {
  const ctx = await makeApp(t);
  const { a, b } = await setupCouple(ctx.baseUrl);

  const memo = (await a.api.post(`/api/daymemos/${todayKey()}`, { body: Buffer.from('bye'), headers: {} })).body;
  const file = path.join(ctx.dataDir, 'media', 'voice', `${memo.mine.id}.m4a`);
  assert.ok(existsSync(file));

  assert.equal((await b.api.del('/api/couple')).status, 200);
  assert.ok(!existsSync(file), 'day-memo audio is cleaned up on dissolve');
});

test('rituals: v2.0 stores without any v3.0 fields serve all new endpoints with empty defaults', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  assert.deepEqual((await a.api.get('/api/daymemos')).body, { days: [], streak: 0 });
  assert.deepEqual((await a.api.get('/api/capsules')).body, { capsules: [] });
  assert.deepEqual((await a.api.get('/api/needs')).body, { needs: [] });
  assert.deepEqual((await a.api.get('/api/goals')).body, { goals: [] });
  assert.deepEqual((await a.api.get('/api/app-events')).body, { events: [] });
  const board = (await a.api.get('/api/weekplan')).body;
  assert.equal(board.days.length, 7);
  assert.equal(board.start, todayKey());
  assert.deepEqual(board.slots, []);
  const couple = (await a.api.get('/api/couple')).body.couple;
  assert.equal(couple.members[0].energy, null);
});
