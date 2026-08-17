import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen, dateKeyDaysAgo } from './helpers.js';

test('daily answers: hidden partner answer, tailored WS payloads, streak over two days', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const yesterday = dateKeyDaysAgo(1);
  const today = dateKeyDaysAgo(0);

  // Nothing answered yet.
  const empty = await a.api.get(`/api/daily/${today}`);
  assert.deepEqual(empty.body, {
    dateKey: today,
    questionId: null,
    questionText: null,
    myAnswer: null,
    partnerAnswer: null,
    bothAnswered: false,
    streak: 0,
    customQuestion: null,
  });

  // Both answer YESTERDAY → streak becomes 1 (consecutive run ends yesterday).
  await a.api.post(`/api/daily/${yesterday}`, { json: { questionId: 41, text: 'the beach day' } });
  const yEntry = await b.api.post(`/api/daily/${yesterday}`, { json: { questionId: 41, text: 'our first trip' } });
  assert.equal(yEntry.body.bothAnswered, true);
  assert.equal(yEntry.body.streak, 1);
  // drain yesterday's daily_answer frames so today's assertions are clean
  await aSock.waitFor('daily_answer', (m) => m.payload.dateKey === yesterday);
  await aSock.waitFor('daily_answer', (m) => m.payload.dateKey === yesterday);
  await bSock.waitFor('daily_answer', (m) => m.payload.dateKey === yesterday);
  await bSock.waitFor('daily_answer', (m) => m.payload.dateKey === yesterday);

  // A answers TODAY: partner answer stays hidden, streak still 1.
  const aFirst = await a.api.post(`/api/daily/${today}`, { json: { questionId: 42, text: 'pancakes 🥞' } });
  assert.equal(aFirst.status, 200);
  assert.deepEqual(aFirst.body, {
    dateKey: today,
    questionId: 42,
    questionText: null,
    myAnswer: 'pancakes 🥞',
    partnerAnswer: null,
    bothAnswered: false,
    streak: 1,
    customQuestion: null,
  });

  // Tailored WS frames: A sees their own answer, B sees myAnswer:null and no partner answer yet.
  const aFrame1 = await aSock.waitFor('daily_answer', (m) => m.payload.dateKey === today);
  assert.equal(aFrame1.payload.myAnswer, 'pancakes 🥞');
  assert.equal(aFrame1.payload.partnerAnswer, null);
  const bFrame1 = await bSock.waitFor('daily_answer', (m) => m.payload.dateKey === today);
  assert.equal(bFrame1.payload.myAnswer, null);
  assert.equal(bFrame1.payload.partnerAnswer, null);
  assert.equal(bFrame1.payload.bothAnswered, false);

  // B answers TODAY → both see both answers, bothAnswered true, streak 2.
  const bAnswer = await b.api.post(`/api/daily/${today}`, { json: { questionId: 42, text: 'waffles 🧇' } });
  assert.deepEqual(bAnswer.body, {
    dateKey: today,
    questionId: 42,
    questionText: null,
    myAnswer: 'waffles 🧇',
    partnerAnswer: 'pancakes 🥞',
    bothAnswered: true,
    streak: 2,
    customQuestion: null,
  });

  const aFrame2 = await aSock.waitFor('daily_answer', (m) => m.payload.dateKey === today && m.payload.bothAnswered);
  assert.equal(aFrame2.payload.myAnswer, 'pancakes 🥞');
  assert.equal(aFrame2.payload.partnerAnswer, 'waffles 🧇');
  assert.equal(aFrame2.payload.streak, 2);
  const bFrame2 = await bSock.waitFor('daily_answer', (m) => m.payload.dateKey === today && m.payload.bothAnswered);
  assert.equal(bFrame2.payload.myAnswer, 'waffles 🧇');
  assert.equal(bFrame2.payload.partnerAnswer, 'pancakes 🥞');

  // GET view for A agrees.
  const aView = await a.api.get(`/api/daily/${today}`);
  assert.equal(aView.body.partnerAnswer, 'waffles 🧇');
  assert.equal(aView.body.streak, 2);
});

test('streak is 0 when the chain is broken (only a day 3 days ago answered)', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const old = dateKeyDaysAgo(3);
  app.store.data.couples[coupleId].daily[old] = {
    questionId: 1,
    answers: {
      [a.memberId]: { text: 'a', answeredAt: new Date().toISOString() },
      [b.memberId]: { text: 'b', answeredAt: new Date().toISOString() },
    },
  };
  app.store.markDirty();
  const res = await a.api.get(`/api/daily/${dateKeyDaysAgo(0)}`);
  assert.equal(res.body.streak, 0);
});

test('daily validation: bad dateKey, missing questionId, missing text', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  assert.equal((await a.api.get('/api/daily/not-a-date')).status, 400);
  assert.equal((await a.api.post('/api/daily/2026-08-03', { json: { text: 'x' } })).status, 400);
  assert.equal((await a.api.post('/api/daily/2026-08-03', { json: { questionId: 1 } })).status, 400);
});

test('daily writes accept only ±1 day and revealed answers cannot be rewritten', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  for (const dateKey of [dateKeyDaysAgo(2), dateKeyDaysAgo(-2)]) {
    const outside = await a.api.post(`/api/daily/${dateKey}`, {
      json: { questionId: 7, text: 'outside window' },
    });
    assert.equal(outside.status, 400);
    assert.equal(outside.body.error, 'bad_datekey');
  }

  const today = dateKeyDaysAgo(0);
  assert.equal((await a.api.post(`/api/daily/${today}`, {
    json: { questionId: 7, text: 'first', clientOperationId: 'daily-first' },
  })).status, 200);
  assert.equal((await a.api.post(`/api/daily/${today}`, {
    json: { questionId: 7, text: 'edited before reveal', clientOperationId: 'daily-edit' },
  })).status, 200);
  assert.ok(app.store.data.couples[coupleId].daily[today].answers[a.memberId].editedAt);
  assert.equal((await b.api.post(`/api/daily/${today}`, {
    json: { questionId: 7, text: 'partner answer' },
  })).status, 200);

  const blocked = await a.api.post(`/api/daily/${today}`, {
    json: { questionId: 7, text: 'silent rewrite' },
  });
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.error, 'daily_revealed');
  const view = await b.api.get(`/api/daily/${today}`);
  assert.equal(view.body.partnerAnswer, 'edited before reveal');
});

test('daily push copy differentiates the roles: first answer nudges, second announces the reveal', async (t) => {
  const deliveries = [];
  const provider = { async send(request) { deliveries.push(request); } };
  const { baseUrl } = await makeApp(t, { pushProvider: provider });
  const { a, b } = await setupCouple(baseUrl);
  await a.api.post('/api/push-devices/current', {
    json: { apnsToken: 'aa'.repeat(32), environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'en' },
  });
  await b.api.post('/api/push-devices/current', {
    json: { apnsToken: 'bb'.repeat(32), environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'de' },
  });
  const waitFor = async (check) => {
    for (let attempt = 0; attempt < 100 && !check(); attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 5));
    }
    assert.ok(check(), 'timed out waiting for asynchronous push delivery');
  };
  const today = dateKeyDaysAgo(0);

  // First answer → the partner who still owes theirs gets the nudge (DE device).
  const secret = 'my hidden answer text';
  await a.api.post(`/api/daily/${today}`, { json: { questionId: 7, text: secret } });
  await waitFor(() => deliveries.length === 1);
  assert.equal(deliveries[0].token, 'bb'.repeat(32));
  assert.equal(deliveries[0].payload.type, 'daily');
  assert.equal(deliveries[0].payload.link, 'sooodreamy://daily');
  assert.equal(deliveries[0].payload.aps.alert.body, 'Mia hat geantwortet — deine fehlt noch 🤫');
  assert.equal(JSON.stringify(deliveries[0].payload).includes(secret), false);

  // Second answer → the waiting partner gets the reveal announcement (EN device).
  await b.api.post(`/api/daily/${today}`, { json: { questionId: 7, text: 'the second answer' } });
  await waitFor(() => deliveries.length === 2);
  assert.equal(deliveries[1].token, 'aa'.repeat(32));
  assert.equal(deliveries[1].payload.type, 'daily_reveal');
  assert.equal(deliveries[1].payload.aps.alert.body, 'You both answered. Ready to reveal? ✨');
  assert.equal(JSON.stringify(deliveries[1].payload).includes('second answer'), false);
});

test('daily answers: a divergent follow-up questionId is refused with the pinned id (409)', async (t) => {
  // Schlussrunde 4 (Bugs): two devices on different builds derive DIFFERENT
  // questions for the same day (pool-growth race, eval repro 410 vs 427).
  // Before the fix the second answer was silently filed under the first
  // question — a couple would reveal answers to two different questions.
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const today = dateKeyDaysAgo(0);

  const first = await a.api.post(`/api/daily/${today}`, { json: { questionId: 410, text: 'the beach, always' } });
  assert.equal(first.status, 200);
  assert.equal(first.body.questionId, 410);

  // Partner's device derived question 427 → refused WITH the authoritative id.
  const clash = await b.api.post(`/api/daily/${today}`, { json: { questionId: 427, text: 'a cabin in the woods' } });
  assert.equal(clash.status, 409);
  assert.equal(clash.body.error, 'daily_question_mismatch');
  assert.equal(clash.body.details.questionId, 410);

  // The refused answer must NOT be filed.
  const entry = await b.api.get(`/api/daily/${today}`);
  assert.equal(entry.body.myAnswer, null);
  assert.equal(entry.body.questionId, 410);

  // Resubmitting under the pinned question lands normally and reveals.
  const fixed = await b.api.post(`/api/daily/${today}`, { json: { questionId: 410, text: 'a cabin in the woods' } });
  assert.equal(fixed.status, 200);
  assert.equal(fixed.body.bothAnswered, true);

  // Same-id answers (the normal path) stay unaffected on later days.
  const widget = await a.api.get('/api/widget-snapshot');
  assert.equal(widget.body.dailyQuestionId, 410, 'widgets read the pinned id from the snapshot');
  // Schlussrunde 5: the snapshot names the day the pin belongs to, so a
  // client whose LOCAL day differs (midnight/timezone straddle) can drop it.
  assert.equal(widget.body.dailyDateKey, today, 'the pin is bound to the server-UTC day');
  assert.equal(widget.body.dailyQuestion, null, 'no stored text without a questionText submit');
});

test('daily questionText: stored with the pin, echoed in entry/snapshot/409 details, never rewritten', async (t) => {
  // Schlussrunde 5 (mixed-version lockout): if the loser of the pin race
  // doesn't KNOW the pinned id (older content pool), it re-renders a
  // different question forever and can never answer. The pinning answer
  // therefore stores the rendered bilingual text so every client can show
  // the authoritative question.
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const today = dateKeyDaysAgo(0);
  const text = { de: 'Was war dein Lieblingsmoment?', en: 'What was your favorite moment?' };

  // Pinning answer stores the (trimmed) text.
  const first = await a.api.post(`/api/daily/${today}`, {
    json: { questionId: 500, text: 'the sunrise', questionText: { de: `  ${text.de}  `, en: `${text.en} ` } },
  });
  assert.equal(first.status, 200);
  assert.deepEqual(first.body.questionText, text);

  // GET entry and widget snapshot carry it for both members.
  assert.deepEqual((await b.api.get(`/api/daily/${today}`)).body.questionText, text);
  const widget = await b.api.get('/api/widget-snapshot');
  assert.deepEqual(widget.body.dailyQuestion, text);
  assert.equal(widget.body.dailyDateKey, today);

  // A divergent second answer is refused WITH id and text.
  const clash = await b.api.post(`/api/daily/${today}`, {
    json: { questionId: 501, text: 'the rain', questionText: { de: 'Andere Frage', en: 'Other question' } },
  });
  assert.equal(clash.status, 409);
  assert.equal(clash.body.error, 'daily_question_mismatch');
  assert.equal(clash.body.details.questionId, 500);
  assert.deepEqual(clash.body.details.questionText, text);

  // A same-id second answer lands — but never rewrites the stored text.
  const second = await b.api.post(`/api/daily/${today}`, {
    json: { questionId: 500, text: 'the rain', questionText: { de: 'Umformuliert', en: 'Reworded' } },
  });
  assert.equal(second.status, 200);
  assert.deepEqual(second.body.questionText, text);
});

test('daily questionText validation: optional for old clients, malformed/oversized → 400', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const today = dateKeyDaysAgo(0);

  const reject = async (questionText) => {
    const res = await a.api.post(`/api/daily/${today}`, { json: { questionId: 7, text: 'x', questionText } });
    assert.equal(res.status, 400);
    assert.equal(res.body.error, 'invalid_request');
  };
  await reject('not-an-object');
  await reject({ de: 'nur deutsch' }); // en missing
  await reject({ de: '   ', en: 'blank de' }); // empty after trim
  await reject({ de: 'ok', en: 'x'.repeat(301) }); // over the 300 limit

  // Old clients omit the field entirely — the pin stores null and the 409
  // details stay honest about it.
  const first = await a.api.post(`/api/daily/${today}`, { json: { questionId: 7, text: 'plain old client' } });
  assert.equal(first.status, 200);
  assert.equal(first.body.questionText, null);
  const clash = await b.api.post(`/api/daily/${today}`, { json: { questionId: 8, text: 'divergent' } });
  assert.equal(clash.status, 409);
  assert.equal(clash.body.details.questionText, null);
});

test('daily replay race: op ids are not remembered on refusal, and the snapshot serves the LOCAL day (Schlussrunde 6)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const today = dateKeyDaysAgo(0);
  const tomorrow = dateKeyDaysAgo(-1);

  await a.api.post(`/api/daily/${today}`, {
    json: { questionId: 410, text: 'sunrise coffee', questionText: { de: 'Frage 410', en: 'Question 410' } },
  });

  // Offline-outbox replay of a stale derivation: refused, and the failed
  // clientOperationId must NOT be remembered — a later retry of the same id
  // stays a mismatch instead of answering {duplicate:true} for nothing.
  const replay = await b.api.post(`/api/daily/${today}`, {
    json: { questionId: 427, text: 'stranded draft', clientOperationId: 'replay-op-1' },
  });
  assert.equal(replay.status, 409);
  assert.equal(replay.body.details.questionId, 410);
  assert.equal(replay.body.details.questionText.de, 'Frage 410');
  const retry = await b.api.post(`/api/daily/${today}`, {
    json: { questionId: 427, text: 'stranded draft', clientOperationId: 'replay-op-1' },
  });
  assert.equal(retry.status, 409, 'a refused op id must stay refused, not turn duplicate');

  // The salvaged re-send under the pinned question (new op id) lands.
  const resend = await b.api.post(`/api/daily/${today}`, {
    json: { questionId: 410, text: 'stranded draft', clientOperationId: 'replay-op-2' },
  });
  assert.equal(resend.status, 200);
  assert.equal(resend.body.bothAnswered, true);

  // Widget snapshot for the caller's LOCAL day: ±1 window accepted, daily
  // block keyed to the requested day, invalid keys refused like every
  // other daily write.
  const local = await a.api.get(`/api/widget-snapshot?dateKey=${today}`);
  assert.equal(local.body.dailyDateKey, today);
  assert.equal(local.body.dailyQuestionId, 410);
  assert.equal(local.body.dailyQuestion.en, 'Question 410');
  assert.equal(local.body.dailyAnsweredByMe, true);
  const ahead = await a.api.get(`/api/widget-snapshot?dateKey=${tomorrow}`);
  assert.equal(ahead.body.dailyDateKey, tomorrow, 'a device already past midnight gets ITS day');
  assert.equal(ahead.body.dailyQuestionId, null, 'tomorrow has no pin yet');
  assert.equal(ahead.body.dailyAnsweredByMe, false);
  assert.equal((await a.api.get('/api/widget-snapshot?dateKey=2020-01-01')).status, 400);
  assert.equal((await a.api.get('/api/widget-snapshot?dateKey=nonsense')).status, 400);
});
