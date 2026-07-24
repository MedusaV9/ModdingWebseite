// Besuche (Doc C §3.4): Haus-Snapshot per REST (JSON ≤ 256 KB, rev-Bump) + Besuchs-Lifecycle
// (VISIT_REQUEST/ACCEPT/DECLINE/END) + Live-POS-Relay über den generischen visit:-Room
// (5-Hz-Drossel macht rooms.js). Bau-Warnung/BUILD_DELTA sind reine Relays (Best-Effort,
// Client-Logik) — der finale Snapshot kommt beim VISIT_END wieder per REST.

import express from 'express';
import { restAuth, FRIEND_CODE_RE } from './auth.js';
import { areFriends } from './friends.js';

export function housesData(ctx) {
  return ctx.store.collection('houses', { houses: {} }); // friendCode -> {blob, rev, sizeBytes, uploadedAt}
}

export function register(ctx) {
  const { hub, cfg } = ctx;
  housesData(ctx);
  // Aktive Besuchs-Freigaben: roomId -> Set<friendCode> (Host + akzeptierte Gäste).
  const allowed = new Map();
  // Offene Besuchsanfragen: "<guestCode>-><hostCode>" -> at
  const pendingReqs = new Map();

  // Nur wer freigeschaltet ist, darf in einen visit:-Room.
  ctx.rooms.registerJoinGuard('visit', (conn, roomId) => {
    const set = allowed.get(roomId);
    if (!set || !set.has(conn.friendCode)) return { ok: false, code: 'BAD_ROOM' };
    return { ok: true };
  });

  hub.on('VISIT_REQUEST', (conn, msg) => {
    const target = typeof msg.d.target === 'string' ? msg.d.target.toUpperCase() : '';
    if (!FRIEND_CODE_RE.test(target) || !ctx.byCode.has(target)) {
      return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    }
    if (target === conn.friendCode) return hub.sendError(conn, 'SELF', { re: msg.seq });
    if (!areFriends(ctx, conn.friendCode, target)) {
      return hub.sendError(conn, 'NOT_FRIENDS', { re: msg.seq });
    }
    const hostDevice = ctx.byCode.get(target);
    if (!hub.isOnline(hostDevice)) return hub.sendError(conn, 'OFFLINE_TARGET', { re: msg.seq });
    pendingReqs.set(`${conn.friendCode}->${target}`, ctx.clock.now());
    hub.send(conn, 'OK', {}, { re: msg.seq });
    hub.sendToDevice(hostDevice, 'VISIT_INCOMING', {
      from: conn.friendCode,
      name: conn.name,
      goobyName: conn.goobyName,
    });
  });

  hub.on('VISIT_ACCEPT', (conn, msg) => {
    const guest = typeof msg.d.guest === 'string' ? msg.d.guest.toUpperCase() : '';
    const key = `${guest}->${conn.friendCode}`;
    if (!pendingReqs.has(key)) return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    pendingReqs.delete(key);
    const roomId = `visit:${conn.friendCode}`;
    allowed.set(roomId, new Set([conn.friendCode, guest]));
    const rev = housesData(ctx).houses[conn.friendCode]?.rev ?? 0;
    const ready = { room: roomId, host: conn.friendCode, guest, rev };
    hub.send(conn, 'VISIT_READY', ready, { re: msg.seq });
    const guestDevice = ctx.byCode.get(guest);
    if (guestDevice) hub.sendToDevice(guestDevice, 'VISIT_READY', ready);
  });

  hub.on('VISIT_DECLINE', (conn, msg) => {
    const guest = typeof msg.d.guest === 'string' ? msg.d.guest.toUpperCase() : '';
    pendingReqs.delete(`${guest}->${conn.friendCode}`);
    hub.send(conn, 'OK', {}, { re: msg.seq });
    const guestDevice = ctx.byCode.get(guest);
    if (guestDevice) hub.sendToDevice(guestDevice, 'VISIT_DENIED', { from: conn.friendCode });
  });

  hub.on('VISIT_END', (conn, msg) => {
    const roomId = typeof msg.d.room === 'string' ? msg.d.room : `visit:${conn.friendCode}`;
    const set = allowed.get(roomId);
    if (!set || !set.has(conn.friendCode)) return hub.sendError(conn, 'NOT_IN_ROOM', { re: msg.seq });
    hub.send(conn, 'OK', {}, { re: msg.seq });
    for (const code of set) {
      const deviceId = ctx.byCode.get(code);
      if (deviceId) {
        hub.sendToDevice(deviceId, 'VISIT_ENDED', { room: roomId, by: conn.friendCode });
        const memberConn = hub.connFor(deviceId);
        if (memberConn) ctx.rooms.leave(memberConn, roomId);
      }
    }
    allowed.delete(roomId);
  });

  // Host disconnectet → Besuch ist vorbei (Room räumt rooms.js via onDisconnect).
  hub.onDisconnect((conn) => {
    const roomId = `visit:${conn.friendCode}`;
    if (allowed.has(roomId)) allowed.delete(roomId);
  });

  // ---- REST: Haus-Snapshot (Upload ≤ 256 KB, Abruf nur für Freunde/Host) ----
  ctx.app.put('/api/house', express.json({ limit: cfg.limits.houseSnapshotBytes }), (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const layout = req.body;
    if (typeof layout !== 'object' || layout === null) {
      return res.status(400).json({ ok: false, code: 'BAD_LAYOUT' });
    }
    const text = JSON.stringify(layout);
    if (Buffer.byteLength(text, 'utf8') > cfg.limits.houseSnapshotBytes) {
      return res.status(413).json({ ok: false, code: 'PAYLOAD_TOO_LARGE' });
    }
    const code = auth.player.friendCode;
    const data = housesData(ctx);
    const entry = data.houses[code] || { rev: 0 };
    entry.rev += 1;
    entry.sizeBytes = Buffer.byteLength(text, 'utf8');
    entry.uploadedAt = ctx.clock.now();
    entry.blob = ctx.store.putBlob('blobs', `house-${code}.json`, text, cfg.limits.houseSnapshotBytes);
    data.houses[code] = entry;
    ctx.store.markDirty('houses');
    res.json({ ok: true, rev: entry.rev });
  });

  ctx.app.get('/api/house/:friendCode', (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const code = String(req.params.friendCode || '').toUpperCase();
    if (!FRIEND_CODE_RE.test(code) || !ctx.byCode.has(code)) {
      return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    }
    const me = auth.player.friendCode;
    if (me !== code && !areFriends(ctx, me, code)) {
      return res.status(403).json({ ok: false, code: 'NOT_FRIENDS' });
    }
    const entry = housesData(ctx).houses[code];
    if (!entry) return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    const blob = ctx.store.readBlob(entry.blob);
    if (!blob) return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    res.json({ ok: true, rev: entry.rev, layout: JSON.parse(blob.toString('utf8')) });
  });
}
