import { DeviceHttp } from './http.mjs';
import { DeviceSocket } from './ws.mjs';
import { Violations } from './violations.mjs';
import { ID_RE, collectStrings, marker } from './util.mjs';

/**
 * The World holds every simulated couple/member/device, the global id→couple
 * ownership registry (the cross-couple detector), the full frame log and the
 * request ledger. Scenario code only talks to the world.
 *
 * IP scheme: device (couple c, member m, device d) binds source address
 * 127.7.<c+1>.<m*100+d+1> — every "phone" is its own household IP, so the
 * server's per-IP rate limits and per-IP socket caps apply per device, like
 * production traffic through a reverse proxy would.
 */
export class World {
  constructor({ baseUrl, rng, log = console.log }) {
    this.baseUrl = baseUrl;
    this.rng = rng;
    this.log = log;
    this.couples = [];
    this.violations = new Violations();
    /** id (or couple code) → coupleIdx that owns it */
    this.idOwner = new Map();
    /** every WS frame any device received: {device, coupleIdx, frame, at} */
    this.frameLog = [];
    this.stats = {
      requests: 0,
      byStatus: {},
      httpErrors: 0,
      frames: 0,
      framesByType: {},
      scenarios: {},
    };
    /** all scheduled Zeitposts the arena created */
    this.scheduledPosts = [];
    this.expectDisconnects = false;
    this.quiesce = false;
    this.deadline = 0;
  }

  bumpScenario(name) {
    this.stats.scenarios[name] = (this.stats.scenarios[name] ?? 0) + 1;
  }

  recordHttp({ device, method, path, result }) {
    this.stats.requests += 1;
    const bucket = String(result.status);
    this.stats.byStatus[bucket] = (this.stats.byStatus[bucket] ?? 0) + 1;
    if (result.status >= 500) {
      this.violations.add('http_5xx', 'critical',
        `${method} ${path} answered ${result.status}`,
        { device, body: result.body });
    }
  }

  recordHttpError({ device, method, path, error }) {
    // Connection errors during a planned restart window are expected.
    if (this.expectDisconnects) return;
    this.stats.httpErrors += 1;
    this.violations.add('http_transport_error', 'high',
      `${method} ${path} failed on ${device}: ${error}`, {});
  }

  /** Registers every id-shaped string in an HTTP response as owned by coupleIdx. */
  harvestIds(coupleIdx, body) {
    for (const str of collectStrings(body)) {
      if (!ID_RE.test(str)) continue;
      const owner = this.idOwner.get(str);
      if (owner === undefined) {
        this.idOwner.set(str, coupleIdx);
      } else if (owner !== coupleIdx) {
        this.violations.add('cross_couple_http', 'critical',
          `HTTP response for couple ${coupleIdx} contains id ${str} owned by couple ${owner}`,
          { id: str, owner, receiver: coupleIdx });
      }
    }
  }

  registerId(id, coupleIdx) {
    if (typeof id === 'string' && id.length > 0) this.idOwner.set(id, coupleIdx);
  }

  recordFrame(device, frame, generation) {
    this.stats.frames += 1;
    this.stats.framesByType[frame.type] = (this.stats.framesByType[frame.type] ?? 0) + 1;
    this.frameLog.push({
      device: device.name,
      coupleIdx: device.ci,
      memberId: device.memberId,
      frame,
      generation,
      at: Date.now(),
    });
  }

  device(ci, mi, di) {
    return this.couples[ci].members[mi].devices[di];
  }

  *allDevices() {
    for (const couple of this.couples) {
      for (const member of couple.members) {
        yield* member.devices;
      }
    }
  }

  /**
   * Creates `count` couples. Member 0 creates, member 1 joins; each member
   * gets `devicesPerMember` device sessions (extra ones via the device-link
   * flow: POST /api/sessions/link-code → POST /api/couples/link) and every
   * device opens its own WebSocket.
   */
  async setup({ couples: count, devicesPerMember }) {
    const setups = [];
    for (let ci = 0; ci < count; ci += 1) {
      setups.push(this.#setupCouple(ci, devicesPerMember));
    }
    await Promise.all(setups);
    this.log(`world: ${count} couples × 2 members × ${devicesPerMember} devices ready`
      + ` (${[...this.allDevices()].length} sockets)`);
  }

  #deviceScaffold(ci, mi, di) {
    const name = `c${ci}m${mi}d${di}`;
    const ip = `127.7.${ci + 1}.${mi * 100 + di + 1}`;
    const device = {
      ci, mi, di, name, ip,
      baseUrl: this.baseUrl,
      deviceId: `arena-c${ci}-m${mi}-d${di}`,
      token: null,
      sessionId: null,
      memberId: null,
      coupleId: null,
      http: null,
      sock: null,
    };
    device.http = new DeviceHttp({
      baseUrl: this.baseUrl, localAddress: ip, world: this, deviceName: name, coupleIdx: ci,
    });
    device.sock = new DeviceSocket({ device, world: this });
    return device;
  }

  async #setupCouple(ci, devicesPerMember) {
    const couple = {
      ci,
      key: `couple${ci}`,
      marker: marker(ci),
      coupleId: null,
      code: null,
      members: [
        { mi: 0, memberId: null, devices: [] },
        { mi: 1, memberId: null, devices: [] },
      ],
      // scenario state
      seq: 0,
      lastMessageId: null,
      lastPulseAt: new Map(),
    };
    this.couples[ci] = couple;

    // Member 0 device 0 creates the couple.
    const a0 = this.#deviceScaffold(ci, 0, 0);
    const created = await a0.http.post('/api/couples', {
      json: {
        name: `Mia${ci}`, avatar: '🦊', color: '#FF5C8A',
        deviceId: a0.deviceId, deviceName: a0.name,
      },
    });
    if (created.status !== 201) throw new Error(`couple ${ci} create failed: ${JSON.stringify(created.body)}`);
    a0.token = created.body.token;
    a0.http.token = created.body.token;
    a0.sessionId = created.body.sessionId;
    a0.memberId = created.body.memberId;
    a0.coupleId = created.body.coupleId;
    couple.coupleId = created.body.coupleId;
    couple.code = created.body.couple.code;
    couple.members[0].memberId = created.body.memberId;
    couple.members[0].devices.push(a0);
    this.registerId(couple.code, ci);
    this.harvestIds(ci, created.body);

    // Member 1 device 0 joins.
    const b0 = this.#deviceScaffold(ci, 1, 0);
    const joined = await b0.http.post('/api/couples/join', {
      json: {
        code: couple.code, name: `Ben${ci}`, avatar: '🐻', color: '#4A90D9',
        deviceId: b0.deviceId, deviceName: b0.name,
      },
    });
    if (joined.status !== 200) throw new Error(`couple ${ci} join failed: ${JSON.stringify(joined.body)}`);
    b0.token = joined.body.token;
    b0.http.token = joined.body.token;
    b0.sessionId = joined.body.sessionId;
    b0.memberId = joined.body.memberId;
    b0.coupleId = joined.body.coupleId;
    couple.members[1].memberId = joined.body.memberId;
    couple.members[1].devices.push(b0);
    this.harvestIds(ci, joined.body);

    // Extra devices per member via the self-service device-link flow.
    for (let mi = 0; mi < 2; mi += 1) {
      const primary = couple.members[mi].devices[0];
      for (let di = 1; di < devicesPerMember; di += 1) {
        const issue = await primary.http.post('/api/sessions/link-code');
        if (issue.status !== 201) throw new Error(`couple ${ci} m${mi} link-code failed: ${JSON.stringify(issue.body)}`);
        const extra = this.#deviceScaffold(ci, mi, di);
        const linked = await extra.http.post('/api/couples/link', {
          json: { code: issue.body.linkCode, deviceId: extra.deviceId, deviceName: extra.name },
        });
        if (linked.status !== 200) throw new Error(`couple ${ci} m${mi} d${di} link failed: ${JSON.stringify(linked.body)}`);
        extra.token = linked.body.token;
        extra.http.token = linked.body.token;
        extra.sessionId = linked.body.sessionId;
        extra.memberId = linked.body.memberId;
        extra.coupleId = linked.body.coupleId;
        couple.members[mi].devices.push(extra);
        this.harvestIds(ci, linked.body);
        // The member's already-connected devices get device_linked fanout —
        // sockets connect below, so only assert no error here.
      }
    }

    // Open every device's WebSocket.
    for (const member of couple.members) {
      for (const device of member.devices) {
        await device.sock.connect();
        await device.sock.waitFor('welcome', (f) => f.payload?.memberId === device.memberId);
      }
    }
  }

  /** Closes all sockets + HTTP agents (end of run). */
  teardown() {
    for (const device of this.allDevices()) {
      device.sock.close({ expected: true });
      device.http.destroy();
    }
  }
}
