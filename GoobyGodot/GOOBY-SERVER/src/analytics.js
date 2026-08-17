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
    // sessionId -> {minutes, day, endedAt} (Upsert-Basis: das JÜNGSTE/längste
    // Update derselben Session gewinnt — E14 P1-2). Alt-Bestand: true.
    sessionIds: {},
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
  let updated = 0;
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
    let minutes = Number.isFinite(s.minutes) ? s.minutes : (s.endedAt - s.startedAt) / 60_000;
    minutes = Math.min(Math.max(minutes, 0), 24 * 60); // Cap: eine Session ≤ 24 h
    minutes = Math.round(minutes * 10) / 10;
    const known = data.sessionIds[s.sessionId];
    if (known) {
      // E14 P1-2: Idempotenter Upsert pro sessionId — das Update mit der
      // LÄNGSTEN Dauer gewinnt (Heartbeat/Reconnect-Flush derselben laufenden
      // Session). Kürzere/gleiche Resends sind Duplikate. Alt-Bestand (true)
      // hat keine Delta-Basis und bleibt Duplikat.
      if (typeof known !== 'object' || !(minutes > known.minutes)) {
        duplicates++;
        continue;
      }
      const delta = Math.round((minutes - known.minutes) * 10) / 10;
      const newDay = dayKey(s.endedAt, cfg.tz);
      const oldBucket = data.days[known.day]?.[deviceId];
      if (oldBucket) {
        oldBucket.minutes = Math.round((oldBucket.minutes - known.minutes) * 10) / 10;
        if (newDay !== known.day) oldBucket.sessions -= 1;
      }
      const dayBucket = (data.days[newDay] ??= {});
      const agg = (dayBucket[deviceId] ??= { minutes: 0, sessions: 0 });
      agg.minutes = Math.round((agg.minutes + minutes) * 10) / 10;
      if (newDay !== known.day || !oldBucket) agg.sessions += 1;
      const pp = (data.perPlayer[deviceId] ??= { minutes: 0, sessions: 0, lastAt: 0 });
      pp.minutes = Math.round((pp.minutes + delta) * 10) / 10;
      pp.lastAt = Math.max(pp.lastAt, s.endedAt);
      const recentRow = data.recent.find(
        (r) => r.sessionId === s.sessionId && r.deviceId === deviceId
      );
      if (recentRow) {
        recentRow.endedAt = s.endedAt;
        recentRow.minutes = minutes;
      }
      data.sessionIds[s.sessionId] = { minutes, day: newDay, endedAt: s.endedAt };
      ctx.store.appendLine(`sessions/sessions-${monthKey(s.endedAt, cfg.tz)}.jsonl`, {
        at: now,
        deviceId,
        kind: 'session',
        update: true,
        sessionId: s.sessionId,
        startedAt: s.startedAt,
        endedAt: s.endedAt,
        minutes,
      });
      updated++;
      continue;
    }
    const day = dayKey(s.endedAt, cfg.tz);
    data.sessionIds[s.sessionId] = { minutes, day, endedAt: s.endedAt };
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
      sessionId: s.sessionId,
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
  // E13 P1-1: Idempotenz (batchId/sessionId) muss einen Crash überleben —
  // synchron persistieren, BEVOR der Client die Bestätigung sieht.
  ctx.store.flushNow('analytics');
  return { status: 200, out: { ok: true, accepted, duplicates, updated } };
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
