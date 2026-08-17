import { httpError, id, nowIso, sendJson, readJsonObject, sha256Hex, todayKey } from './util.js';

/**
 * Eigene Tagesfragen (v7.0) — the couple extends the daily-question pool.
 *
 * Each member writes questions the OTHER should answer some day. The server
 * deterministically declares roughly every third day a "custom day" and picks
 * one eligible question (created before that day, not deleted). Who wrote it
 * stays hidden from the partner until BOTH answered — the classic reveal.
 *
 * Privacy of authorship: `GET /api/daily-questions` returns only the CALLER's
 * questions, so the partner cannot look the author up before the reveal.
 *
 * Mixed-version honesty: pre-7.0 clients ignore the `customQuestion` field and
 * keep showing the built-in pack question. Custom days only ever exist after
 * someone on 7.0+ added questions, so mixed pairs stay consistent by default.
 */

const QUESTION_LIMITS = {
  perCouple: 200,
  text: 240,
};

/** Every Nth day (with a non-empty eligible pool) asks a couple question. */
const CUSTOM_DAY_CADENCE = 3;

/** `[{id, text, createdBy, createdOn (dateKey), createdAt}]` */
export function customQuestionsOf(couple) {
  if (!couple.customQuestions) couple.customQuestions = [];
  return couple.customQuestions;
}

function hashInt(seed) {
  return Number.parseInt(sha256Hex(seed).slice(0, 8), 16);
}

/**
 * The live deterministic pick for a date — or null when the date is not a
 * custom day. Only questions created BEFORE `dateKey` are eligible, so a
 * freshly added question never gives its author away on the same day.
 */
export function customQuestionForDay(couple, dateKey) {
  const eligible = customQuestionsOf(couple).filter((q) => q.createdOn < dateKey);
  if (eligible.length === 0) return null;
  if (hashInt(`${couple.id}|${dateKey}|customday`) % CUSTOM_DAY_CADENCE !== 0) return null;
  return eligible[hashInt(`${couple.id}|${dateKey}|pick`) % eligible.length];
}

/**
 * Pins the live pick onto the daily record (first answer wins) so later pool
 * edits can never change an already-asked question. Call before storing an
 * answer for `dateKey`.
 */
export function snapshotCustomQuestion(couple, dateKey) {
  const rec = couple.daily?.[dateKey];
  if (!rec || rec.customQuestion !== undefined) return;
  const live = customQuestionForDay(couple, dateKey);
  rec.customQuestion = live
    ? { id: live.id, text: live.text, createdBy: live.createdBy }
    : null;
}

/**
 * The `customQuestion` field of a daily-entry view: `{id, text, authorId}`
 * or null. `authorId` is only present for the author themselves — or for
 * everyone once both answered (the reveal moment).
 */
export function customQuestionView(couple, dateKey, memberId, bothAnswered) {
  const snapshot = couple.daily?.[dateKey]?.customQuestion;
  const question = snapshot !== undefined ? snapshot : customQuestionForDay(couple, dateKey);
  if (!question) return null;
  const authorId = question.createdBy;
  return {
    id: question.id,
    text: question.text,
    authorId: bothAnswered || authorId === memberId ? authorId : null,
  };
}

export function registerDailyQuestionRoutes(route, h) {
  const { asString } = h;

  // Only MY questions — authorship of the partner's pool stays a surprise.
  route('GET', '/api/daily-questions', { auth: true }, (c) => {
    const mine = customQuestionsOf(c.auth.couple)
      .filter((q) => q.createdBy === c.auth.memberId)
      .map((q) => ({ id: q.id, text: q.text, createdOn: q.createdOn, createdAt: q.createdAt }));
    sendJson(c.res, 200, { questions: mine, poolSize: customQuestionsOf(c.auth.couple).length });
  });

  route('POST', '/api/daily-questions', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const text = asString(body.text, 'text', { max: QUESTION_LIMITS.text });
    const pool = customQuestionsOf(c.auth.couple);
    if (pool.length >= QUESTION_LIMITS.perCouple) {
      throw httpError(413, 'too_many_questions',
        `At most ${QUESTION_LIMITS.perCouple} custom questions per couple — delete one first`);
    }
    const question = {
      id: id('cq'),
      text,
      createdBy: c.auth.memberId,
      createdOn: todayKey(),
      createdAt: nowIso(),
    };
    pool.push(question);
    c.store.markDirty();
    sendJson(c.res, 201, {
      question: { id: question.id, text: question.text, createdOn: question.createdOn, createdAt: question.createdAt },
      poolSize: pool.length,
    });
  });

  route('DELETE', '/api/daily-questions/:id', { auth: true }, (c) => {
    const pool = customQuestionsOf(c.auth.couple);
    const question = pool.find((q) => q.id === c.params.id);
    if (!question) throw httpError(404, 'not_found', 'Unknown custom question');
    if (question.createdBy !== c.auth.memberId) {
      throw httpError(403, 'not_yours', 'Only the author may delete a custom question');
    }
    pool.splice(pool.indexOf(question), 1);
    c.store.markDirty();
    sendJson(c.res, 200, { ok: true, poolSize: pool.length });
  });
}
