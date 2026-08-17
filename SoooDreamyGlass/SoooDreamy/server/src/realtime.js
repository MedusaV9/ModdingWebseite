import { WebSocketServer } from 'ws';
import { nowIso } from './util.js';
import { authenticateToken, requestKey, requireSecureTransport, sessionOrigin } from './security.js';

const HEARTBEAT_MS = 30_000;
const MAX_PAYLOAD_BYTES = 64 * 1024;
const MAX_BUFFERED_BYTES = 256 * 1024;
const MAX_CONNECTIONS = 128;
const MAX_CONNECTIONS_PER_IP = 16;
const MAX_CONNECTIONS_PER_SESSION = 4;
const MAX_CONNECTIONS_PER_MEMBER = 8;
const UPGRADE_WINDOW_MS = 60_000;
const MAX_UPGRADES_PER_IP = 60;

/**
 * WebSocket layer: authenticated `/ws` on the same server. Bearer tokens are
 * accepted only in the `Authorization` header — never in the URL, where
 * proxies, browser history and access logs would leak them. Tracks presence
 * (member online = at least one open socket), heartbeats every 30 s, and
 * offers broadcast helpers used by the REST handlers.
 *
 * Frames are JSON: { type, payload, ts } — plus an optional top-level
 * `origin` ({memberId, deviceId, sessionSuffix}) on member-caused frames so
 * multi-device clients can tell their own events from partner events (and
 * from their own OTHER devices). Old clients ignore the unknown field.
 */
export class Realtime {
  constructor({ store, log = () => {}, security = {} }) {
    this.store = store;
    this.log = log;
    this.security = security;
    this.closing = false;
    /** @type {Map<string, Map<string, Set<import('ws').WebSocket>>>} coupleId -> memberId -> sockets */
    this.sockets = new Map();
    this.upgradeBuckets = new Map();
    this.wss = new WebSocketServer({
      noServer: true,
      maxPayload: MAX_PAYLOAD_BYTES,
      perMessageDeflate: false,
    });
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
    requireSecureTransport(req, this.security);
    const ip = requestKey(req);
    if (!this.#consumeUpgrade(ip)) {
      this.#rejectUpgrade(socket, 429, 'Too Many Requests', { 'Retry-After': '60' });
      return;
    }
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname !== '/ws') {
      this.#rejectUpgrade(socket, 404, 'Not Found');
      return;
    }
    if (url.searchParams.has('token') || url.searchParams.has('access_token')) {
      this.#rejectUpgrade(socket, 400, 'Bad Request');
      return;
    }
    const header = req.headers.authorization;
    const token = typeof header === 'string' && header.startsWith('Bearer ') ? header.slice(7).trim() : null;
    let authenticated = null;
    try {
      authenticated = token ? authenticateToken(this.store, token) : null;
    } catch (err) {
      // Quarantined couple data → honest 503 instead of a misleading 401.
      const status = err.status === 503 ? '503 Service Unavailable' : '401 Unauthorized';
      socket.write(`HTTP/1.1 ${status}\r\nConnection: close\r\n\r\n`);
      socket.destroy();
      return;
    }
    if (!authenticated) {
      this.#rejectUpgrade(socket, 401, 'Unauthorized');
      return;
    }
    if (!this.#withinConnectionCaps(ip, authenticated.record)) {
      this.#rejectUpgrade(socket, 429, 'Too Many Requests', { 'Retry-After': '30' });
      return;
    }
    this.wss.handleUpgrade(req, socket, head, (ws) => {
      this.#onConnection(ws, authenticated.record, ip);
    });
  }

  #consumeUpgrade(ip) {
    const now = Date.now();
    let bucket = this.upgradeBuckets.get(ip);
    if (!bucket || bucket.resetAt <= now) bucket = { count: 0, resetAt: now + UPGRADE_WINDOW_MS };
    bucket.count += 1;
    this.upgradeBuckets.set(ip, bucket);
    if (this.upgradeBuckets.size > 10_000) {
      for (const [key, value] of this.upgradeBuckets) {
        if (value.resetAt <= now) this.upgradeBuckets.delete(key);
      }
    }
    return bucket.count <= MAX_UPGRADES_PER_IP;
  }

  #withinConnectionCaps(ip, record) {
    if (this.wss.clients.size >= MAX_CONNECTIONS) return false;
    let ipCount = 0;
    let sessionCount = 0;
    let memberCount = 0;
    for (const ws of this.wss.clients) {
      if (ws.remoteIp === ip) ipCount += 1;
      if (ws.sessionId === record.sessionId) sessionCount += 1;
      if (ws.coupleId === record.coupleId && ws.memberId === record.memberId) memberCount += 1;
    }
    return ipCount < MAX_CONNECTIONS_PER_IP
      && sessionCount < MAX_CONNECTIONS_PER_SESSION
      && memberCount < MAX_CONNECTIONS_PER_MEMBER;
  }

  #rejectUpgrade(socket, status, reason, headers = {}) {
    const extra = Object.entries(headers).map(([key, value]) => `${key}: ${value}\r\n`).join('');
    socket.write(`HTTP/1.1 ${status} ${reason}\r\n${extra}Connection: close\r\n\r\n`);
    socket.destroy();
  }

  #onConnection(ws, record, remoteIp) {
    const { coupleId, memberId, sessionId } = record;
    ws.isAlive = true;
    ws.coupleId = coupleId;
    ws.memberId = memberId;
    ws.sessionId = sessionId;
    ws.remoteIp = remoteIp;
    // Origin marker for frames this socket causes (typing, canvas_live, …).
    ws.origin = sessionOrigin(record);
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
      // `echo` lets clients correlate pong←ping and use the frame's `ts`
      // (server time) for clock-offset estimation (v3.0 haptic duet).
      this.#send(ws, 'pong', { echo: msg.payload?.echo ?? null });
    } else if (msg.type === 'typing') {
      // Stays partner-only ON PURPOSE: a member's own second device has no
      // use for a "you are typing" echo (it never renders the caller's own
      // typing bubble). The origin marker still lets the partner's devices
      // track per-device typing state when the partner types on two devices.
      this.broadcastPartner(ws.coupleId, ws.memberId, 'typing', {
        memberId: ws.memberId,
        isTyping: Boolean(msg.payload?.isTyping),
      }, { origin: ws.origin });
    } else if (msg.type === 'heartbeat_tap') {
      // v3.0 live heartbeat: fire-and-forget tap relay onto the partner's
      // 3D heart. Not persisted — pure realtime delight.
      const raw = Number(msg.payload?.intensity);
      this.broadcastPartner(ws.coupleId, ws.memberId, 'heartbeat_tap', {
        memberId: ws.memberId,
        intensity: Number.isFinite(raw) ? Math.min(1, Math.max(0, raw)) : 0.7,
      }, { origin: ws.origin });
    } else if (msg.type === 'canvas_live') {
      // Live co-drawing on the shared canvas: the in-progress stroke is
      // relayed but never persisted — the finished stroke still arrives
      // via POST /api/canvas/strokes (which converges all devices). Same
      // fire-and-forget as `typing`. The relayed frame carries the CURRENT
      // board generation (sync contract f) so receivers can drop live ink
      // that raced a clear.
      const width = Number(msg.payload?.width);
      const couple = this.store.data.couples[ws.coupleId];
      this.broadcastPartner(ws.coupleId, ws.memberId, 'canvas_live', {
        memberId: ws.memberId,
        phase: typeof msg.payload?.phase === 'string' ? msg.payload.phase : 'draw',
        color: typeof msg.payload?.color === 'string' ? msg.payload.color.slice(0, 9) : '#FF5C8A',
        width: Number.isFinite(width) ? Math.min(32, Math.max(1, width)) : 5,
        tool: typeof msg.payload?.tool === 'string' ? msg.payload.tool.slice(0, 16) : 'pen',
        points: Array.isArray(msg.payload?.points) ? msg.payload.points.slice(0, 400) : [],
        generation: couple?.canvasGeneration ?? 1,
      }, { origin: ws.origin });
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
    if (this.closing) return;

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

  #send(ws, type, payload, origin = null) {
    if (ws.readyState !== ws.OPEN) return;
    if (ws.bufferedAmount > MAX_BUFFERED_BYTES) {
      ws.close(1013, 'realtime backpressure limit');
      return;
    }
    const frame = origin
      ? { type, payload, ts: nowIso(), origin }
      : { type, payload, ts: nowIso() };
    ws.send(JSON.stringify(frame), (err) => {
      if (err) this.log('ws: send failed', err.message);
    });
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
  broadcastCouple(coupleId, type, payload, { origin = null } = {}) {
    const members = this.sockets.get(coupleId);
    if (!members) return;
    for (const set of members.values()) {
      for (const ws of set) this.#send(ws, type, payload, origin);
    }
  }

  /** Sends to every socket of the couple except the given member's sockets. */
  broadcastPartner(coupleId, memberId, type, payload, { origin = null } = {}) {
    const members = this.sockets.get(coupleId);
    if (!members) return;
    for (const [mid, set] of members) {
      if (mid === memberId) continue;
      for (const ws of set) this.#send(ws, type, payload, origin);
    }
  }

  /**
   * Sends to every socket of one specific member. `exceptSessionId` skips the
   * sockets of one session — used for the touch/haptic self-echo, where the
   * device that fired the REST call already rendered the action locally and
   * only the member's OTHER devices need to converge.
   */
  sendToMember(coupleId, memberId, type, payload, { origin = null, exceptSessionId = null } = {}) {
    const set = this.#memberSet(coupleId, memberId);
    if (!set) return;
    for (const ws of set) {
      if (exceptSessionId !== null && ws.sessionId === exceptSessionId) continue;
      this.#send(ws, type, payload, origin);
    }
  }

  /**
   * Facade bound to one request's session: identical broadcast surface, but
   * every frame carries that session's origin marker. Handed to route
   * handlers so ALL REST-triggered broadcasts are attributable without
   * threading an extra argument through a hundred call sites.
   */
  withOrigin(origin) {
    if (!origin) return this;
    const base = this;
    return {
      isOnline: (coupleId, memberId) => base.isOnline(coupleId, memberId),
      broadcastCouple: (coupleId, type, payload, opts = {}) =>
        base.broadcastCouple(coupleId, type, payload, { origin, ...opts }),
      broadcastPartner: (coupleId, memberId, type, payload, opts = {}) =>
        base.broadcastPartner(coupleId, memberId, type, payload, { origin, ...opts }),
      sendToMember: (coupleId, memberId, type, payload, opts = {}) =>
        base.sendToMember(coupleId, memberId, type, payload, { origin, ...opts }),
      closeCouple: (coupleId) => base.closeCouple(coupleId),
      closeSession: (sessionId, reason) => base.closeSession(sessionId, reason),
    };
  }

  /** Gracefully closes all sockets of a couple (queued frames are flushed first). */
  closeCouple(coupleId) {
    const members = this.sockets.get(coupleId);
    if (!members) return;
    for (const set of members.values()) {
      for (const ws of set) ws.close(1000, 'couple dissolved');
    }
  }

  /** Closes sockets authenticated by a rotated/revoked device session. */
  closeSession(sessionId, reason = 'session revoked') {
    for (const ws of this.wss.clients) {
      if (ws.sessionId === sessionId) ws.close(4001, reason);
    }
  }

  close() {
    this.closing = true;
    clearInterval(this.heartbeat);
    for (const ws of this.wss.clients) ws.terminate();
    this.wss.close();
  }
}
