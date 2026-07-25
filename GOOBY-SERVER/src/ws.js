// WS-Hub (Doc C §1/§2): Verbindungs-Registry, HELLO/WELCOME (TOFU), PING/PONG-Heartbeat,
// Envelope-Dispatch mit re-Korrelation, Rate-Limits. Feature-Module registrieren Handler
// über hub.on(TYPE, fn) und WELCOME-Zusatzdaten über hub.addWelcomeProvider(fn).

import { WebSocketServer } from 'ws';
import { parseEnvelope, buildMsg, buildError, sanitizeName } from './protocol.js';
import { LIMITS } from './ratelimit.js';
import {
  hashSecret,
  secretMatches,
  validDeviceId,
  validSecret,
  newFriendCode,
} from './auth.js';

const HELLO_TIMEOUT_MS = 5000;

export class Hub {
  constructor(ctx) {
    this.ctx = ctx;
    this.handlers = new Map(); // t -> fn(conn, msg)
    this.welcomeProviders = []; // fn(conn) -> partial d
    this.authHooks = []; // fn(conn) nach erfolgreichem HELLO
    this.disconnectHooks = []; // fn(conn) bei Close (nur authentifizierte)
    this.conns = new Map(); // deviceId -> conn
    this.wss = null;
    this.idleTimer = null;

    this.on('PING', (conn, msg) => {
      this.send(conn, 'PONG', { serverTime: this.ctx.clock.now() }, { re: msg.seq });
    });
    this.on('PROFILE_UPDATE', (conn, msg) => this._profileUpdate(conn, msg));
    this.on('SYNC', (conn, msg) => this._sync(conn, msg));
  }

  on(type, fn) {
    this.handlers.set(type, fn);
  }

  addWelcomeProvider(fn) {
    this.welcomeProviders.push(fn);
  }

  onAuthenticated(fn) {
    this.authHooks.push(fn);
  }

  onDisconnect(fn) {
    this.disconnectHooks.push(fn);
  }

  attach(httpServer) {
    const { cfg } = this.ctx;
    this.wss = new WebSocketServer({ noServer: true, maxPayload: 4 * cfg.limits.wsFrameBytes });
    httpServer.on('upgrade', (req, socket, head) => {
      let pathname = '/';
      try {
        pathname = new URL(req.url, 'http://local').pathname;
      } catch {
        socket.destroy();
        return;
      }
      if (pathname !== '/ws') {
        socket.destroy();
        return;
      }
      this.wss.handleUpgrade(req, socket, head, (ws) => this._onConnection(ws, req));
    });
    // Heartbeat-Wächter: 3 verpasste Intervalle (Doc C §1.2) → Drop, Presence → offline.
    const idleMs = 3 * cfg.heartbeatSec * 1000;
    this.idleTimer = setInterval(() => {
      const now = this.ctx.clock.now();
      for (const conn of [...this.conns.values()]) {
        if (now - conn.lastSeenAt > idleMs) conn.ws.close(4000, 'HEARTBEAT_TIMEOUT');
      }
    }, 5000);
    if (this.idleTimer.unref) this.idleTimer.unref();
  }

  _onConnection(ws, req) {
    const conn = {
      ws,
      ip: req.socket.remoteAddress || '?',
      deviceId: null,
      friendCode: null,
      name: null,
      goobyName: null,
      presence: null, // {kind,label}
      rooms: new Set(),
      connectedAt: this.ctx.clock.now(),
      lastSeenAt: this.ctx.clock.now(),
    };
    const helloTimer = setTimeout(() => {
      if (!conn.deviceId) {
        this.sendError(conn, 'HELLO_REQUIRED');
        ws.close(4001, 'HELLO_REQUIRED');
      }
    }, HELLO_TIMEOUT_MS);
    if (helloTimer.unref) helloTimer.unref();

    ws.on('message', (raw, isBinary) => {
      if (isBinary) {
        this.sendError(conn, 'BAD_MESSAGE');
        return;
      }
      this._onMessage(conn, raw);
    });
    ws.on('close', () => {
      clearTimeout(helloTimer);
      this._onClose(conn);
    });
    ws.on('error', () => {
      /* close folgt */
    });
  }

  _onMessage(conn, raw) {
    const { ctx } = this;
    conn.lastSeenAt = ctx.clock.now();
    const key = conn.deviceId ? `ws:${conn.deviceId}` : `ws:ip:${conn.ip}`;
    if (!ctx.buckets.take(key, LIMITS.wsMsg)) {
      this.sendError(conn, 'RATE_LIMIT');
      return;
    }
    const parsed = parseEnvelope(raw, ctx.cfg.limits.wsFrameBytes);
    if (!parsed.ok) {
      if (parsed.code === 'PROTO_VERSION') {
        conn.ws.send(buildMsg('ERROR', { code: 'PROTO_VERSION', min: 1, max: 1 }));
        conn.ws.close(4002, 'PROTO_VERSION');
      } else {
        this.sendError(conn, parsed.code);
      }
      return;
    }
    const msg = parsed.msg;
    if (!conn.deviceId && msg.t !== 'HELLO') {
      this.sendError(conn, 'HELLO_REQUIRED', { re: msg.seq });
      conn.ws.close(4001, 'HELLO_REQUIRED');
      return;
    }
    if (msg.t === 'HELLO') {
      this._hello(conn, msg);
      return;
    }
    const handler = this.handlers.get(msg.t);
    if (!handler) {
      this.sendError(conn, 'UNKNOWN_TYPE', { re: msg.seq });
      return;
    }
    try {
      handler(conn, msg);
    } catch (err) {
      this.ctx.log.error(`[hub] handler ${msg.t} warf:`, err);
      this.sendError(conn, 'BAD_MESSAGE', { re: msg.seq });
    }
  }

  // ---- HELLO → WELCOME (TOFU, Doc C §1.2/§3.1/§7) ----
  _hello(conn, msg) {
    const { ctx } = this;
    const d = msg.d;
    if (!ctx.buckets.take(`hello:${conn.ip}`, LIMITS.hello)) {
      this.sendError(conn, 'RATE_LIMIT', { re: msg.seq });
      conn.ws.close(4003, 'RATE_LIMIT');
      return;
    }
    const deviceId = d.deviceId;
    const secret = d.deviceSecret;
    // Kanonisch name/goobyName; Doc-C-Aliase playerName/goobyNick werden akzeptiert.
    const name = sanitizeName(d.name ?? d.playerName, ctx.cfg.limits.nameLen);
    const goobyName =
      sanitizeName(d.goobyName ?? d.goobyNick, ctx.cfg.limits.nameLen) || 'Gooby';

    if (!validDeviceId(deviceId) || !validSecret(secret)) {
      this.sendError(conn, 'AUTH_FAIL', { re: msg.seq, message: 'deviceId/deviceSecret ungültig' });
      conn.ws.close(4004, 'AUTH_FAIL');
      return;
    }
    let player = ctx.players[deviceId];
    if (player) {
      if (!secretMatches(secret, player.secretHash)) {
        this.sendError(conn, 'AUTH_FAIL', { re: msg.seq });
        conn.ws.close(4004, 'AUTH_FAIL');
        return;
      }
      if (player.banned) {
        this.sendError(conn, 'BANNED', { re: msg.seq });
        conn.ws.close(4005, 'BANNED');
        return;
      }
      if (name) player.name = name;
      player.goobyName = goobyName;
    } else {
      if (!name) {
        this.sendError(conn, 'BAD_MESSAGE', { re: msg.seq, message: 'name fehlt' });
        conn.ws.close(4006, 'BAD_MESSAGE');
        return;
      }
      player = {
        secretHash: hashSecret(secret),
        friendCode: newFriendCode(ctx.players),
        name,
        goobyName,
        createdAt: ctx.clock.now(),
        coins: 0,
        coinsUpdatedAt: null,
        banned: false,
      };
      ctx.players[deviceId] = player;
      ctx.byCode.set(player.friendCode, deviceId);
    }
    player.lastSeenAt = ctx.clock.now();
    if (d.appVersion) player.appVersion = String(d.appVersion).slice(0, 24);
    ctx.store.markDirty('players');

    // Eine Verbindung pro Gerät: alte wird verdrängt.
    const old = this.conns.get(deviceId);
    if (old && old !== conn) {
      this.send(old, 'GOING_DOWN', { reason: 'REPLACED' });
      old.replaced = true;
      old.ws.close(4007, 'REPLACED');
    }
    conn.deviceId = deviceId;
    conn.friendCode = player.friendCode;
    conn.name = player.name;
    conn.goobyName = player.goobyName;
    this.conns.set(deviceId, conn);

    const welcome = {
      friendCode: player.friendCode,
      serverTime: ctx.clock.now(),
      heartbeatSec: ctx.cfg.heartbeatSec,
      features: ['friends', 'presence', 'pal', 'codes', 'events', 'visits', 'boardgames', 'analytics'],
      pendingEvents: [],
      palPending: [],
      friendRequests: [],
    };
    for (const provider of this.welcomeProviders) {
      Object.assign(welcome, provider(conn) || {});
    }
    this.send(conn, 'WELCOME', welcome, { re: msg.seq });
    for (const hook of this.authHooks) hook(conn);
  }

  _profileUpdate(conn, msg) {
    const { ctx } = this;
    const player = ctx.players[conn.deviceId];
    const name = sanitizeName(msg.d.name ?? msg.d.playerName, ctx.cfg.limits.nameLen);
    const goobyName = sanitizeName(msg.d.goobyName ?? msg.d.goobyNick, ctx.cfg.limits.nameLen);
    if (name) {
      player.name = name;
      conn.name = name;
    }
    if (goobyName) {
      player.goobyName = goobyName;
      conn.goobyName = goobyName;
    }
    ctx.store.markDirty('players');
    this.send(conn, 'OK', {}, { re: msg.seq });
  }

  // Coins-ANZEIGE-Cache (Doc C §3.2): Client bleibt autoritativ, Server cached nur.
  _sync(conn, msg) {
    const coins = msg.d.coins;
    if (!Number.isInteger(coins) || coins < 0 || coins > 100_000_000) return;
    const player = this.ctx.players[conn.deviceId];
    player.coins = coins;
    player.coinsUpdatedAt = this.ctx.clock.now();
    this.ctx.store.markDirty('players');
  }

  _onClose(conn) {
    if (!conn.deviceId) return;
    if (this.conns.get(conn.deviceId) === conn) this.conns.delete(conn.deviceId);
    const player = this.ctx.players[conn.deviceId];
    if (player) {
      player.lastSeenAt = this.ctx.clock.now();
      this.ctx.store.markDirty('players');
    }
    if (!conn.replaced) {
      for (const hook of this.disconnectHooks) hook(conn);
    }
  }

  // ---- Versand-Helfer ----
  send(conn, t, d, { re } = {}) {
    if (conn.ws.readyState === conn.ws.OPEN) {
      conn.ws.send(buildMsg(t, d, { re }));
    }
  }

  sendError(conn, code, { re, message } = {}) {
    if (conn.ws.readyState === conn.ws.OPEN) {
      conn.ws.send(buildError(code, { re, message }));
    }
  }

  // true NUR wenn der Socket wirklich OPEN ist und der Frame rausging —
  // Socket-Queueing/CLOSING zählt NIE als Zustellung (E13 P1-2).
  sendToDevice(deviceId, t, d) {
    const conn = this.conns.get(deviceId);
    if (!conn || conn.ws.readyState !== conn.ws.OPEN) return false;
    this.send(conn, t, d);
    return true;
  }

  isOnline(deviceId) {
    return this.conns.has(deviceId);
  }

  connFor(deviceId) {
    return this.conns.get(deviceId) || null;
  }

  onlineConns() {
    return [...this.conns.values()];
  }

  closeAll(reason = 'SHUTDOWN') {
    for (const conn of this.conns.values()) {
      this.send(conn, 'GOING_DOWN', { reason });
      conn.ws.close(1001, reason);
    }
    if (this.idleTimer) clearInterval(this.idleTimer);
    if (this.wss) this.wss.close();
  }
}
