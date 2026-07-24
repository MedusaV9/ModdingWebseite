// Online-Codes (Doc C §4): Panel-CRUD (anlegen/deaktivieren), Client-Redeem via REST —
// 1× pro deviceId, maxUses, Gültigkeitsfenster, Rate-Limit 5/15 min pro Gerät.
// (Offline-Codes bleiben Client-Sache — Doppelstrategie; der Client fragt den Server nur
// für ihm unbekannte Codes.)

import express from 'express';
import { restAuth } from './auth.js';
import { LIMITS } from './ratelimit.js';

const CODE_RE = /^[A-Z0-9][A-Z0-9-]{2,23}$/;

export function codesData(ctx) {
  return ctx.store.collection('codes', { codes: {} });
}

// Panel-seitig: Code anlegen. reward = freies JSON-Objekt (Client wendet es über seinen
// lokalen Reward-Pfad an, z. B. {"coins":500,"sticker":"sonne"}).
export function createCode(ctx, { code, reward, maxUses, validFrom, validUntil }) {
  const data = codesData(ctx);
  const name = String(code || '').trim().toUpperCase();
  if (!CODE_RE.test(name)) return { ok: false, code: 'BAD_CODE' };
  if (data.codes[name]) return { ok: false, code: 'DUPLICATE' };
  if (typeof reward !== 'object' || reward === null || Array.isArray(reward)) {
    return { ok: false, code: 'BAD_REWARD' };
  }
  data.codes[name] = {
    reward,
    maxUses: Number.isInteger(maxUses) && maxUses > 0 ? maxUses : null, // null = unbegrenzt
    uses: 0,
    perDevice: 1,
    active: true,
    validFrom: Number.isFinite(validFrom) ? validFrom : null,
    validUntil: Number.isFinite(validUntil) ? validUntil : null,
    createdAt: ctx.clock.now(),
    createdBy: 'admin',
    redemptions: {}, // deviceId -> at
  };
  ctx.store.markDirty('codes');
  return { ok: true, name };
}

export function deactivateCode(ctx, code) {
  const data = codesData(ctx);
  const entry = data.codes[String(code || '').trim().toUpperCase()];
  if (!entry) return { ok: false, code: 'NOT_FOUND' };
  entry.active = false;
  ctx.store.markDirty('codes');
  return { ok: true };
}

export function redeem(ctx, deviceId, rawCode, now) {
  const data = codesData(ctx);
  const name = String(rawCode || '').trim().toUpperCase();
  const entry = CODE_RE.test(name) ? data.codes[name] : null;
  if (!entry) return { ok: false, code: 'UNKNOWN' };
  if (!entry.active) return { ok: false, code: 'INACTIVE' };
  if (entry.validFrom && now < entry.validFrom) return { ok: false, code: 'NOT_YET_VALID' };
  if (entry.validUntil && now > entry.validUntil) return { ok: false, code: 'EXPIRED' };
  if (entry.redemptions[deviceId]) return { ok: false, code: 'ALREADY_REDEEMED' };
  if (entry.maxUses !== null && entry.uses >= entry.maxUses) return { ok: false, code: 'EXHAUSTED' };
  entry.uses += 1;
  entry.redemptions[deviceId] = now;
  ctx.store.markDirty('codes');
  return { ok: true, reward: entry.reward };
}

export function register(ctx) {
  codesData(ctx);
  ctx.app.post('/api/codes/redeem', express.json({ limit: '4kb' }), (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    if (!ctx.buckets.take(`redeem:${auth.deviceId}`, LIMITS.codesRedeem)) {
      return res.status(429).json({ ok: false, code: 'RATE_LIMIT' });
    }
    res.json(redeem(ctx, auth.deviceId, req.body?.code, ctx.clock.now()));
  });
}
