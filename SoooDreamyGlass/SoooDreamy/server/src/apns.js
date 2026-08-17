import { readFile } from 'node:fs/promises';
import http2 from 'node:http2';
import { createPrivateKey, sign } from 'node:crypto';

const APNS_HOSTS = Object.freeze({
  development: 'https://api.sandbox.push.apple.com',
  production: 'https://api.push.apple.com',
});
const TOKEN_TTL_MS = 50 * 60 * 1000;
const MAX_PAYLOAD_BYTES = 4_096;

function jwtPart(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function apnsError(status, reason) {
  const error = new Error(`APNs rejected the notification (${status}: ${reason})`);
  error.code = reason;
  error.status = status;
  error.permanent = status === 410 || ['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered']
    .includes(reason);
  return error;
}

/**
 * Minimal APNs HTTP/2 provider using token authentication.
 *
 * No Apple key is bundled. `fromEnvironment()` returns null unless the
 * operator explicitly enables APNs and provides team/key ids plus a readable
 * .p8 file. The rest of the server remains fully functional while gated.
 */
export class ApnsProvider {
  constructor({ teamId, keyId, privateKey, timeoutMs = 10_000 }) {
    this.teamId = teamId;
    this.keyId = keyId;
    this.privateKey = privateKey?.type === 'private' && typeof privateKey.export === 'function'
      ? privateKey
      : createPrivateKey(privateKey);
    this.timeoutMs = timeoutMs;
    this.cachedToken = null;
    this.cachedTokenAt = 0;
  }

  static async fromEnvironment({ env = process.env, log = () => {} } = {}) {
    if (env.APNS_ENABLED !== '1') return null;
    const required = ['APNS_TEAM_ID', 'APNS_KEY_ID', 'APNS_PRIVATE_KEY_FILE'];
    const missing = required.filter((name) => typeof env[name] !== 'string' || env[name].trim() === '');
    if (missing.length > 0) {
      log(`push: APNs gated; missing ${missing.join(', ')}`);
      return null;
    }
    try {
      const privateKey = await readFile(env.APNS_PRIVATE_KEY_FILE, 'utf8');
      return new ApnsProvider({
        teamId: env.APNS_TEAM_ID.trim(),
        keyId: env.APNS_KEY_ID.trim(),
        privateKey,
      });
    } catch (error) {
      log('push: APNs gated; private key could not be loaded', error?.code ?? 'unknown');
      return null;
    }
  }

  providerToken(now = Date.now()) {
    if (this.cachedToken && now - this.cachedTokenAt < TOKEN_TTL_MS) return this.cachedToken;
    const header = jwtPart({ alg: 'ES256', kid: this.keyId });
    const claims = jwtPart({ iss: this.teamId, iat: Math.floor(now / 1000) });
    const unsigned = `${header}.${claims}`;
    const signature = sign('sha256', Buffer.from(unsigned), {
      key: this.privateKey,
      dsaEncoding: 'ieee-p1363',
    }).toString('base64url');
    this.cachedToken = `${unsigned}.${signature}`;
    this.cachedTokenAt = now;
    return this.cachedToken;
  }

  async send({ token, environment, bundleId, payload, idempotencyKey }) {
    const host = APNS_HOSTS[environment];
    if (!host) throw new TypeError(`Unsupported APNs environment: ${environment}`);
    const body = JSON.stringify(payload);
    if (Buffer.byteLength(body) > MAX_PAYLOAD_BYTES) {
      throw new TypeError('APNs payload exceeds 4096 bytes');
    }

    const client = http2.connect(host);
    client.setTimeout(this.timeoutMs, () => client.destroy(new Error('APNs connection timed out')));
    try {
      const result = await new Promise((resolve, reject) => {
        let settled = false;
        const finish = (callback, value) => {
          if (settled) return;
          settled = true;
          callback(value);
        };
        client.once('error', (error) => finish(reject, error));
        const request = client.request({
          ':method': 'POST',
          ':path': `/3/device/${token}`,
          authorization: `bearer ${this.providerToken()}`,
          'apns-topic': bundleId,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          ...(idempotencyKey ? { 'apns-id': idempotencyKey } : {}),
          'content-type': 'application/json',
        });
        let status = 0;
        const chunks = [];
        request.on('response', (headers) => {
          status = Number(headers[':status'] ?? 0);
        });
        request.on('data', (chunk) => {
          if (chunks.reduce((total, item) => total + item.length, 0) < 8_192) chunks.push(chunk);
        });
        request.once('error', (error) => finish(reject, error));
        request.once('end', () => {
          let response = {};
          try {
            response = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
          } catch {
            // APNs errors normally contain JSON; preserve a bounded generic reason otherwise.
          }
          finish(resolve, { status, reason: response.reason ?? 'Unknown' });
        });
        request.end(body);
      });
      if (result.status !== 200) throw apnsError(result.status, result.reason);
    } finally {
      client.close();
    }
  }
}
