// Analytics (Doc C §4): Session-Batches per REST, offline-gepuffert vom Client, idempotent
// über batchId UND sessionId. Rohdaten: JSONL (sessions/sessions-YYYY-MM.jsonl, rotiert).
// Aggregation (fürs Panel — WICHTIGSTE Seite): Spielzeit pro Tag & Spieler ("wann, wie
// lange, wie oft"): days[dayKey][deviceId] = {minutes, sessions}, Stunden-Histogramm,
// letzte Sessions fürs Dashboard.

import express from 'express';
import { restAuth } from './auth.js';
import { dayKey, monthKey } from './config.js';

const RECENT_CAP = 50;
const ID_RE = /^[A-Za-z0-9._-]{6,64}$/;

export function analyticsData(ctx) {
  return ctx.store.collection('analytics', {
    batches: {}, // batchId -> at (Idempotenz)
    sessionIds: {}, // sessionId -> true (Dedupe über Batch-Grenzen)
    days: {}, // dayKey -> deviceId -> {minutes, sessions}
    hours: {}, // "0".."23" -> Session-Starts (wann wird gespielt)
    perPlayer: {}, // deviceId -> {minutes, sessions, lastAt}
    recent: [], // letzte Sessions fürs Dashboard
  });
}

function hourInTz(tsMs, tz) {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: tz,
    hour: '2-digit',
    hour12: false,
  }).format(new Date(tsMs));
}

export function ingestBatch(ctx, deviceId, body, now) {
  const { cfg } = ctx;
  const data = analyticsData(ctx);
  const batchId = body?.batchId;
  const sessions = body?.sessions;
  if (typeof batchId !== 'string' || !ID_RE.test(batchId)) {
    return { status: 400, out: { ok: false, code: 'BAD_BATCH_ID' } };
  }
  if (!Array.isArray(sessions) || sessions.length === 0) {
    return { status: 400, out: { ok: false, code: 'BAD_SESSIONS' } };
  }
  if (sessions.length > cfg.limits.analyticsBatchSessions) {
    return { status: 400, out: { ok: false, code: 'BATCH_TOO_LARGE' } };
  }
  if (data.batches[batchId]) {
    return { status: 200, out: { ok: true, accepted: 0, duplicates: sessions.length, idempotent: true } };
  }
  let accepted = 0;
  let duplicates = 0;
  for (const s of sessions) {
    if (
      typeof s?.sessionId !== 'string' ||
      !ID_RE.test(s.sessionId) ||
      !Number.isFinite(s.startedAt) ||
      !Number.isFinite(s.endedAt) ||
      s.endedAt < s.startedAt
    ) {
      duplicates += 0; // ungültige Session: still überspringen (Batch bleibt nutzbar)
      continue;
    }
    if (data.sessionIds[s.sessionId]) {
      duplicates++;
      continue;
    }
    let minutes = Number.isFinite(s.minutes) ? s.minutes : (s.endedAt - s.startedAt) / 60_000;
    minutes = Math.min(Math.max(minutes, 0), 24 * 60); // Cap: eine Session ≤ 24 h
    minutes = Math.round(minutes * 10) / 10;
    data.sessionIds[s.sessionId] = true;
    const day = dayKey(s.endedAt, cfg.tz);
    const dayBucket = (data.days[day] ??= {});
    const agg = (dayBucket[deviceId] ??= { minutes: 0, sessions: 0 });
    agg.minutes = Math.round((agg.minutes + minutes) * 10) / 10;
    agg.sessions += 1;
    const hour = hourInTz(s.startedAt, cfg.tz);
    data.hours[hour] = (data.hours[hour] || 0) + 1;
    const pp = (data.perPlayer[deviceId] ??= { minutes: 0, sessions: 0, lastAt: 0 });
    pp.minutes = Math.round((pp.minutes + minutes) * 10) / 10;
    pp.sessions += 1;
    pp.lastAt = Math.max(pp.lastAt, s.endedAt);
    data.recent.push({
      deviceId,
      startedAt: s.startedAt,
      endedAt: s.endedAt,
      minutes,
      appVersion: typeof s.appVersion === 'string' ? s.appVersion.slice(0, 24) : null,
    });
    if (data.recent.length > RECENT_CAP) data.recent.splice(0, data.recent.length - RECENT_CAP);
    ctx.store.appendLine(`sessions/sessions-${monthKey(s.endedAt, cfg.tz)}.jsonl`, {
      at: now,
      deviceId,
      kind: 'session',
      sessionId: s.sessionId,
      startedAt: s.startedAt,
      endedAt: s.endedAt,
      minutes,
    });
    accepted++;
  }
  data.batches[batchId] = now;
  ctx.store.markDirty('analytics');
  return { status: 200, out: { ok: true, accepted, duplicates } };
}

export function register(ctx) {
  analyticsData(ctx);
  ctx.app.post('/api/analytics', express.json({ limit: '256kb' }), (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const { status, out } = ingestBatch(ctx, auth.deviceId, req.body, ctx.clock.now());
    res.status(status).json(out);
  });
}
