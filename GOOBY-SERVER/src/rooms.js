// Generische Rooms (Doc C §1.3): visit:/board:/drive:/mg:/gobnom:/gvz: — join/leave/msg-Relay.
// Server validiert NUR: Mitgliedschaft, Payload-Größe (≤ 8 KB), Rate, Kind-Format.
// Feature-Logik dockt über kindHooks (z. B. Boardgames-Turn-Ownership) und joinGuards an.
// Geld/Items laufen NIE über ROOM_MSG (eigene validierte Typen, z. B. PAL_SEND).

import { LIMITS } from './ratelimit.js';

const ROOM_RE = /^(visit|board|drive|mg|gobnom|gvz):[A-Za-z0-9._-]{1,64}$/;
const KIND_RE = /^[A-Z][A-Z0-9_]{0,23}$/;
// Kapazität PRO PRÄFIX (RANCH-DLC-IDEAS-4 §1.1 Punkt 1): ein globales
// MAX_MEMBERS=4 würde Besuche/Brettspiele unbeabsichtigt zu Mehrpersonen-
// räumen machen. mg: (Ranch-Minispiele/Ausritt) darf 4; Rest bleibt 2.
// room.meta.maxMembers (z. B. Besuch über mg: = 2) deckelt zusätzlich.
const MAX_MEMBERS_BY_PREFIX = { visit: 2, board: 2, drive: 2, mg: 4, gobnom: 2, gvz: 2 };

export class Rooms {
  constructor(ctx) {
    this.ctx = ctx;
    this.rooms = new Map(); // roomId -> {id, members:Set<deviceId>, createdAt, meta:{}}
    this.kindHooks = new Map(); // kind -> fn(conn, room, body, msg) => {ok:true}|{ok:false,code}
    this.joinGuards = new Map(); // prefix -> fn(conn, roomId) => {ok:true}|{ok:false,code}
    this.leaveHooks = []; // fn(conn, roomId, {disconnect})
    this.joinHooks = []; // fn(conn, room)
  }

  registerKindHook(kind, fn) {
    this.kindHooks.set(kind, fn);
  }

  registerJoinGuard(prefix, fn) {
    this.joinGuards.set(prefix, fn);
  }

  onLeave(fn) {
    this.leaveHooks.push(fn);
  }

  onJoin(fn) {
    this.joinHooks.push(fn);
  }

  get(roomId) {
    return this.rooms.get(roomId) || null;
  }

  ensure(roomId, meta = {}) {
    let room = this.rooms.get(roomId);
    if (!room) {
      room = { id: roomId, members: new Set(), createdAt: this.ctx.clock.now(), meta };
      this.rooms.set(roomId, room);
    }
    return room;
  }

  join(conn, roomId) {
    if (typeof roomId !== 'string' || !ROOM_RE.test(roomId)) return { ok: false, code: 'BAD_ROOM' };
    const prefix = roomId.split(':', 1)[0];
    const guard = this.joinGuards.get(prefix);
    if (guard) {
      const verdict = guard(conn, roomId);
      if (!verdict.ok) return verdict;
    }
    const room = this.ensure(roomId);
    let cap = MAX_MEMBERS_BY_PREFIX[prefix] ?? 2;
    if (Number.isInteger(room.meta.maxMembers)) cap = Math.min(cap, room.meta.maxMembers);
    if (!room.members.has(conn.deviceId) && room.members.size >= cap) {
      return { ok: false, code: 'ROOM_FULL' };
    }
    const isNew = !room.members.has(conn.deviceId);
    room.members.add(conn.deviceId);
    conn.rooms.add(roomId);
    if (isNew) {
      this._broadcast(room, conn.deviceId, 'ROOM_PEER_JOINED', {
        room: roomId,
        friendCode: conn.friendCode,
        name: conn.name,
        goobyName: conn.goobyName,
      });
    }
    for (const hook of this.joinHooks) hook(conn, room);
    return { ok: true, room };
  }

  leave(conn, roomId, { disconnect = false } = {}) {
    const room = this.rooms.get(roomId);
    conn.rooms.delete(roomId);
    if (!room || !room.members.has(conn.deviceId)) return;
    room.members.delete(conn.deviceId);
    this._broadcast(room, conn.deviceId, 'ROOM_PEER_LEFT', {
      room: roomId,
      friendCode: conn.friendCode,
    });
    for (const hook of this.leaveHooks) hook(conn, roomId, { disconnect });
    // board:-Räume räumt boardgames.js selbst auf (120-s-Rejoin-Fenster).
    if (room.members.size === 0 && !roomId.startsWith('board:')) {
      this.rooms.delete(roomId);
    }
  }

  destroy(roomId) {
    this.rooms.delete(roomId);
  }

  _broadcast(room, exceptDeviceId, t, d) {
    for (const memberId of room.members) {
      if (memberId === exceptDeviceId) continue;
      this.ctx.hub.sendToDevice(memberId, t, d);
    }
  }

  relay(conn, room, kind, body) {
    this._broadcast(room, conn.deviceId, 'ROOM_MSG', {
      room: room.id,
      kind,
      body,
      from: { friendCode: conn.friendCode, goobyName: conn.goobyName },
    });
  }
}

export function register(ctx) {
  const rooms = new Rooms(ctx);
  ctx.rooms = rooms;
  const { hub, cfg } = ctx;

  hub.on('ROOM_JOIN', (conn, msg) => {
    const verdict = rooms.join(conn, msg.d.room);
    if (!verdict.ok) {
      hub.sendError(conn, verdict.code, { re: msg.seq });
      return;
    }
    const members = [...verdict.room.members].map((id) => ctx.players[id]?.friendCode);
    hub.send(conn, 'OK', { room: verdict.room.id, members }, { re: msg.seq });
  });

  hub.on('ROOM_LEAVE', (conn, msg) => {
    if (typeof msg.d.room === 'string') rooms.leave(conn, msg.d.room);
    hub.send(conn, 'OK', {}, { re: msg.seq });
  });

  hub.on('ROOM_MSG', (conn, msg) => {
    const { room: roomId, kind, body } = msg.d;
    const room = typeof roomId === 'string' ? rooms.get(roomId) : null;
    if (!room || !room.members.has(conn.deviceId)) {
      hub.sendError(conn, 'NOT_IN_ROOM', { re: msg.seq });
      return;
    }
    if (typeof kind !== 'string' || !KIND_RE.test(kind)) {
      hub.sendError(conn, 'BAD_KIND', { re: msg.seq });
      return;
    }
    const payload = body === undefined || body === null ? {} : body;
    if (JSON.stringify(payload).length > cfg.limits.roomBodyBytes) {
      hub.sendError(conn, 'PAYLOAD_TOO_LARGE', { re: msg.seq });
      return;
    }
    // POS-Relay ist auf 5 Hz gedrosselt (Besuch, Doc C §3.4).
    if (kind === 'POS' && !ctx.buckets.take(`pos:${conn.deviceId}:${roomId}`, LIMITS.roomPos)) {
      return; // still verwerfen — veraltete Positionen sind wertlos
    }
    const hook = rooms.kindHooks.get(kind);
    if (hook) {
      const verdict = hook(conn, room, payload, msg);
      if (!verdict.ok) {
        hub.sendError(conn, verdict.code, { re: msg.seq });
        return;
      }
      if (verdict.suppressRelay) return;
    }
    rooms.relay(conn, room, kind, payload);
  });

  // Disconnect → alle Rooms verlassen (Peers sehen ROOM_PEER_LEFT).
  hub.onDisconnect((conn) => {
    for (const roomId of [...conn.rooms]) rooms.leave(conn, roomId, { disconnect: true });
  });
}
