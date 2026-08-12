import { WebSocketServer } from 'ws';
import { nowIso } from './util.js';

const HEARTBEAT_MS = 30_000;

/**
 * WebSocket layer: /ws?token=… on the same http server. Tracks presence
 * (member online = at least one open socket), heartbeats every 30 s, and
 * offers broadcast helpers used by the REST handlers.
 *
 * Frames are JSON: { type, payload, ts }.
 */
export class Realtime {
  constructor({ store, log = () => {} }) {
    this.store = store;
    this.log = log;
    /** @type {Map<string, Map<string, Set<import('ws').WebSocket>>>} coupleId -> memberId -> sockets */
    this.sockets = new Map();
    this.wss = new WebSocketServer({ noServer: true });
    this.heartbeat = setInterval(() => this.#pingAll(), HEARTBEAT_MS);
    this.heartbeat.unref?.();
  }

  attach(httpServer) {
    httpServer.on('upgrade', (req, socket, head) => {
      try {
        this.#onUpgrade(req, socket, head);
      } catch (err) {
        this.log('ws: upgrade failed', err);
        socket.destroy();
      }
    });
  }

  #onUpgrade(req, socket, head) {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname !== '/ws') {
      socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }
    const token = url.searchParams.get('token');
    const auth = token ? this.store.data.tokens[token] : undefined;
    const couple = auth ? this.store.data.couples[auth.coupleId] : undefined;
    if (!auth || !couple) {
      socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }
    this.wss.handleUpgrade(req, socket, head, (ws) => this.#onConnection(ws, auth.coupleId, auth.memberId));
  }

  #onConnection(ws, coupleId, memberId) {
    ws.isAlive = true;
    ws.coupleId = coupleId;
    ws.memberId = memberId;
    ws.on('pong', () => {
      ws.isAlive = true;
    });
    ws.on('message', (data) => {
      try {
        this.#onMessage(ws, data);
      } catch (err) {
        this.log('ws: message handling failed', err);
      }
    });
    ws.on('close', () => this.#onClose(ws));
    ws.on('error', (err) => this.log('ws: socket error', err.message));

    const set = this.#memberSet(coupleId, memberId, true);
    set.add(ws);
    const firstSocket = set.size === 1;

    const couple = this.store.data.couples[coupleId];
    const partner = couple?.members.find((m) => m.id !== memberId);
    this.#send(ws, 'welcome', {
      memberId,
      coupleId,
      partnerOnline: partner ? this.isOnline(coupleId, partner.id) : false,
    });
    if (firstSocket) {
      this.broadcastPartner(coupleId, memberId, 'presence', { memberId, online: true });
    }
  }

  #onMessage(ws, data) {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return; // ignore malformed frames
    }
    if (!msg || typeof msg.type !== 'string') return;
    if (msg.type === 'ping') {
      this.#send(ws, 'pong', {});
    } else if (msg.type === 'typing') {
      this.broadcastPartner(ws.coupleId, ws.memberId, 'typing', {
        memberId: ws.memberId,
        isTyping: Boolean(msg.payload?.isTyping),
      });
    }
    // Unknown client frames are ignored on purpose.
  }

  #onClose(ws) {
    const { coupleId, memberId } = ws;
    const members = this.sockets.get(coupleId);
    const set = members?.get(memberId);
    if (!set) return;
    set.delete(ws);
    if (set.size > 0) return;
    members.delete(memberId);
    if (members.size === 0) this.sockets.delete(coupleId);

    // Last socket of this member closed -> mark offline. The couple may be
    // gone already (dissolved) — skip presence bookkeeping in that case.
    const couple = this.store.data.couples[coupleId];
    const member = couple?.members.find((m) => m.id === memberId);
    if (!member) return;
    member.lastSeenAt = nowIso();
    this.store.markDirty();
    this.broadcastPartner(coupleId, memberId, 'presence', {
      memberId,
      online: false,
      lastSeenAt: member.lastSeenAt,
    });
  }

  #memberSet(coupleId, memberId, create = false) {
    let members = this.sockets.get(coupleId);
    if (!members) {
      if (!create) return undefined;
      members = new Map();
      this.sockets.set(coupleId, members);
    }
    let set = members.get(memberId);
    if (!set) {
      if (!create) return undefined;
      set = new Set();
      members.set(memberId, set);
    }
    return set;
  }

  #send(ws, type, payload) {
    if (ws.readyState !== ws.OPEN) return;
    ws.send(JSON.stringify({ type, payload, ts: nowIso() }));
  }

  #pingAll() {
    for (const ws of this.wss.clients) {
      if (ws.isAlive === false) {
        ws.terminate();
        continue;
      }
      ws.isAlive = false;
      ws.ping();
    }
  }

  isOnline(coupleId, memberId) {
    const set = this.#memberSet(coupleId, memberId);
    return Boolean(set && set.size > 0);
  }

  /** Sends to every open socket of the couple (all devices of both members). */
  broadcastCouple(coupleId, type, payload) {
    const members = this.sockets.get(coupleId);
    if (!members) return;
    for (const set of members.values()) {
      for (const ws of set) this.#send(ws, type, payload);
    }
  }

  /** Sends to every socket of the couple except the given member's sockets. */
  broadcastPartner(coupleId, memberId, type, payload) {
    const members = this.sockets.get(coupleId);
    if (!members) return;
    for (const [mid, set] of members) {
      if (mid === memberId) continue;
      for (const ws of set) this.#send(ws, type, payload);
    }
  }

  /** Sends to every socket of one specific member. */
  sendToMember(coupleId, memberId, type, payload) {
    const set = this.#memberSet(coupleId, memberId);
    if (!set) return;
    for (const ws of set) this.#send(ws, type, payload);
  }

  /** Gracefully closes all sockets of a couple (queued frames are flushed first). */
  closeCouple(coupleId) {
    const members = this.sockets.get(coupleId);
    if (!members) return;
    for (const set of members.values()) {
      for (const ws of set) ws.close(1000, 'couple dissolved');
    }
  }

  close() {
    clearInterval(this.heartbeat);
    for (const ws of this.wss.clients) ws.terminate();
    this.wss.close();
  }
}
