// Admin-Events (Doc C §4): Panel löst Events aus → sofortiger WS-Push (SERVER_EVENT) an
// passende Online-Clients + Pull-Queue für Offline-Clients (WELCOME.pendingEvents beim Boot).
// deliveredTo pro Gerät verhindert Doppel-Zustellung, expiresAt verhindert Uralt-Events.

import crypto from 'node:crypto';

export function eventsData(ctx) {
  return ctx.store.collection('events', { events: {} });
}

function eventPayload(id, evt) {
  return { id, type: evt.type, params: evt.params, at: evt.at, expiresAt: evt.expiresAt };
}

function matchesTarget(evt, friendCode) {
  return evt.target === 'all' || evt.target === friendCode;
}

// Panel-seitig: Event auslösen. target = "all" | "GOOBY-XXXX", ttlMin default 24 h.
export function triggerEvent(ctx, { type, params, target, ttlMin }) {
  const cleanType = String(type || '').trim().toUpperCase();
  if (!/^[A-Z][A-Z0-9_]{1,39}$/.test(cleanType)) return { ok: false, code: 'BAD_TYPE' };
  if (params !== undefined && (typeof params !== 'object' || params === null || Array.isArray(params))) {
    return { ok: false, code: 'BAD_PARAMS' };
  }
  const cleanTarget = target === 'all' || !target ? 'all' : String(target).trim().toUpperCase();
  const now = ctx.clock.now();
  const ttl = Number.isFinite(ttlMin) && ttlMin > 0 ? ttlMin : 24 * 60;
  const id = `evt-${crypto.randomBytes(6).toString('hex')}`;
  const evt = {
    type: cleanType,
    params: params || {},
    target: cleanTarget,
    at: now,
    expiresAt: now + ttl * 60_000,
    deliveredTo: [],
  };
  const data = eventsData(ctx);
  data.events[id] = evt;

  // Push an alle passenden Online-Clients (deliveredTo merken).
  let pushed = 0;
  for (const conn of ctx.hub.onlineConns()) {
    if (!matchesTarget(evt, conn.friendCode)) continue;
    if (ctx.hub.sendToDevice(conn.deviceId, 'SERVER_EVENT', eventPayload(id, evt))) {
      evt.deliveredTo.push(conn.deviceId);
      pushed++;
    }
  }
  ctx.store.markDirty('events');
  return { ok: true, id, pushed };
}

// Boot-Pull: unzugestellte, nicht abgelaufene Events für dieses Gerät (markiert zugestellt).
export function pendingEventsFor(ctx, deviceId, friendCode) {
  const data = eventsData(ctx);
  const now = ctx.clock.now();
  const out = [];
  let dirty = false;
  for (const [id, evt] of Object.entries(data.events)) {
    if (evt.expiresAt <= now) continue;
    if (!matchesTarget(evt, friendCode)) continue;
    if (evt.deliveredTo.includes(deviceId)) continue;
    evt.deliveredTo.push(deviceId);
    out.push(eventPayload(id, evt));
    dirty = true;
  }
  if (dirty) ctx.store.markDirty('events');
  return out;
}

// Aufräumen (beim Start + täglich): Events, die > 7 Tage abgelaufen sind, löschen.
export function pruneEvents(ctx) {
  const data = eventsData(ctx);
  const cutoff = ctx.clock.now() - 7 * 24 * 3600_000;
  let dirty = false;
  for (const [id, evt] of Object.entries(data.events)) {
    if (evt.expiresAt < cutoff) {
      delete data.events[id];
      dirty = true;
    }
  }
  if (dirty) ctx.store.markDirty('events');
}

export function register(ctx) {
  eventsData(ctx);
  pruneEvents(ctx);
  ctx.hub.addWelcomeProvider((conn) => ({
    pendingEvents: pendingEventsFor(ctx, conn.deviceId, conn.friendCode),
  }));
}
