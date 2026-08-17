import http from 'node:http';

/**
 * Minimal JSON HTTP client on node:http so every simulated device can bind
 * its OWN loopback source address (127.7.x.y). The server rate-limits and
 * caps connections per client IP (`requestKey(req)` = socket.remoteAddress),
 * so distinct source IPs make N couples from one test box behave like N real
 * households — without touching any server limit.
 *
 * Every request is recorded into `world.stats` (count, status buckets,
 * 5xx bodies) — invariant (h) "no 5xx" is derived from this ledger.
 */
export class DeviceHttp {
  constructor({ baseUrl, localAddress, world, deviceName, coupleIdx = null }) {
    const url = new URL(baseUrl);
    this.host = url.hostname;
    this.port = Number(url.port || 80);
    this.localAddress = localAddress;
    this.world = world;
    this.deviceName = deviceName;
    this.coupleIdx = coupleIdx;
    this.token = null;
    // Own agent per device: connections must originate from the device's
    // source IP, so agents cannot be shared across devices. Keep-alive stays
    // OFF: node's server closes idle keep-alive sockets after 5 s, and a
    // request racing onto a just-closed socket surfaces as ECONNRESET — real
    // clients retry these transparently, but the arena must attribute every
    // response deterministically.
    this.agent = new http.Agent({ keepAlive: false, maxSockets: 12, localAddress });
  }

  request(method, path, { json, body, headers = {}, timeoutMs = 15_000 } = {}) {
    const requestHeaders = { ...headers };
    if (this.token) requestHeaders.authorization = `Bearer ${this.token}`;
    let payload = body ?? null;
    if (json !== undefined) {
      payload = Buffer.from(JSON.stringify(json));
      requestHeaders['content-type'] = 'application/json';
    }
    if (payload) requestHeaders['content-length'] = Buffer.byteLength(payload);
    const startedAt = Date.now();
    return new Promise((resolve, reject) => {
      const req = http.request({
        host: this.host,
        port: this.port,
        method,
        path,
        headers: requestHeaders,
        agent: this.agent,
        localAddress: this.localAddress,
        timeout: timeoutMs,
      }, (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          const raw = Buffer.concat(chunks);
          const contentType = res.headers['content-type'] ?? '';
          let parsed = raw;
          if (contentType.includes('application/json')) {
            try {
              parsed = JSON.parse(raw.toString('utf8'));
            } catch {
              parsed = { parseError: true, raw: raw.toString('utf8').slice(0, 500) };
            }
          }
          const result = {
            status: res.statusCode,
            body: parsed,
            headers: res.headers,
            ms: Date.now() - startedAt,
          };
          this.world?.recordHttp({
            device: this.deviceName, method, path, result,
          });
          // Cross-couple detector: every id in a response of THIS couple's
          // device registers as owned by this couple; a registry conflict
          // means the server served foreign data.
          if (this.coupleIdx !== null && parsed && typeof parsed === 'object' && !Buffer.isBuffer(parsed)) {
            this.world?.harvestIds(this.coupleIdx, parsed);
          }
          resolve(result);
        });
      });
      req.on('timeout', () => {
        req.destroy(new Error(`HTTP timeout after ${timeoutMs} ms: ${method} ${path}`));
      });
      req.on('error', (err) => {
        this.world?.recordHttpError({ device: this.deviceName, method, path, error: err.message });
        reject(err);
      });
      if (payload) req.write(payload);
      req.end();
    });
  }

  get(path, options) { return this.request('GET', path, options); }
  post(path, options) { return this.request('POST', path, options); }
  put(path, options) { return this.request('PUT', path, options); }
  patch(path, options) { return this.request('PATCH', path, options); }
  del(path, options) { return this.request('DELETE', path, options); }

  destroy() {
    this.agent.destroy();
  }
}
