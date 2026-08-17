import WebSocket from 'ws';

/**
 * One device's realtime socket. Records EVERY received frame into the
 * device's frame log (fed to the post-run invariant pass), supports
 * `waitFor(type, pred)` for scenario assertions, and reports unexpected
 * closes — a socket dying outside a planned reconnect/restart window is an
 * invariant (h) violation.
 */
export class DeviceSocket {
  constructor({ device, world }) {
    this.device = device;
    this.world = world;
    this.ws = null;
    this.connected = false;
    this.expectedClose = false;
    this.waiters = [];
    this.unconsumed = [];
    this.generation = 0; // bumps on every (re)connect — frames tag it
  }

  connect({ timeoutMs = 8_000 } = {}) {
    this.expectedClose = false;
    this.generation += 1;
    const generation = this.generation;
    // Per-CONNECTION expected flag: under load the close handshake of the
    // previous socket can outlive the next connect() — a shared per-instance
    // flag would then mis-report the old socket's close as unexpected.
    const conn = { expected: false };
    this.currentConn = conn;
    const { baseUrl, token, ip, name } = this.device;
    const ws = new WebSocket(`${baseUrl.replace(/^http/, 'ws')}/ws`, {
      headers: { authorization: `Bearer ${token}` },
      localAddress: ip,
    });
    this.ws = ws;
    ws.on('message', (data) => {
      let frame;
      try {
        frame = JSON.parse(data.toString());
      } catch {
        this.world.violations.add('ws_bad_json', 'high',
          `device ${name} received a non-JSON WS frame`, { raw: data.toString().slice(0, 200) });
        return;
      }
      this.world.recordFrame(this.device, frame, generation);
      const idx = this.waiters.findIndex((w) => w.match(frame));
      if (idx !== -1) this.waiters.splice(idx, 1)[0].resolve(frame);
      else {
        this.unconsumed.push(frame);
        if (this.unconsumed.length > 2_000) this.unconsumed.splice(0, 1_000);
      }
    });
    ws.on('close', (code, reason) => {
      if (ws === this.ws) this.connected = false;
      if (!conn.expected && !this.world.expectDisconnects) {
        this.world.violations.add('unexpected_ws_close', 'high',
          `device ${name} socket closed unexpectedly (code ${code})`,
          { code, reason: reason?.toString?.().slice(0, 120) });
      }
    });
    ws.on('error', (err) => {
      if (!conn.expected && !this.world.expectDisconnects) {
        this.world.violations.add('ws_error', 'high',
          `device ${name} socket error: ${err.message}`, {});
      }
    });
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`WS connect timeout for ${name}`)), timeoutMs);
      ws.once('open', () => {
        clearTimeout(timer);
        this.connected = true;
        resolve();
      });
      ws.once('error', (err) => {
        clearTimeout(timer);
        reject(err);
      });
    });
  }

  /** Resolves with the first frame (past or future) matching type+pred. */
  waitFor(type, pred = () => true, timeoutMs = 6_000) {
    const match = (frame) => frame.type === type && pred(frame);
    const idx = this.unconsumed.findIndex(match);
    if (idx !== -1) return Promise.resolve(this.unconsumed.splice(idx, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = {
        match,
        resolve: (frame) => {
          clearTimeout(timer);
          resolve(frame);
        },
      };
      const timer = setTimeout(() => {
        const at = this.waiters.indexOf(waiter);
        if (at !== -1) this.waiters.splice(at, 1);
        reject(new Error(`timeout waiting for "${type}" on ${this.device.name}`));
      }, timeoutMs);
      this.waiters.push(waiter);
    });
  }

  /** True when a matching frame is already buffered (no waiting). */
  sawFrame(type, pred = () => true) {
    return this.unconsumed.some((frame) => frame.type === type && pred(frame));
  }

  send(frame) {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(frame));
  }

  close({ expected = true } = {}) {
    this.expectedClose = expected;
    if (this.currentConn && expected) this.currentConn.expected = true;
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      this.ws.close();
    }
    this.connected = false;
  }

  terminate() {
    this.expectedClose = true;
    if (this.currentConn) this.currentConn.expected = true;
    this.ws?.terminate?.();
    this.connected = false;
  }
}
