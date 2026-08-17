import { randomUUID } from 'node:crypto';
import { id, nowIso } from './util.js';

const MAX_DEVICES_PER_MEMBER = 8;
const MAX_ALERT_TITLE = 120;
const MAX_ALERT_BODY = 240;
const DEFAULT_MAX_OUTBOX_ENTRIES = 256;
const DEFAULT_MAX_ATTEMPTS = 8;
const DEFAULT_RETRY_BASE_MS = 5_000;
const DEFAULT_RETRY_MAX_MS = 60 * 60_000;
const MAX_DELIVERIES_PER_SWEEP = 32;

function devicesOf(couple) {
  if (!Array.isArray(couple.pushDevices)) couple.pushDevices = [];
  return couple.pushDevices;
}

function outboxOf(couple) {
  if (!Array.isArray(couple.pushOutbox)) couple.pushOutbox = [];
  return couple.pushOutbox;
}

function localized(value, language) {
  if (value && typeof value === 'object') {
    return value[language] ?? value.en ?? value.de ?? '';
  }
  return value ?? '';
}

/**
 * Provider boundary for killed-app delivery.
 *
 * Production supplies an adapter whose `send({ token, environment, payload })`
 * talks to APNs. This repository intentionally does not contain Apple keys;
 * without an injected provider notifications are registered but reported as
 * gated instead of pretending they were delivered.
 */
export class PushService {
  constructor({
    provider = null,
    log = () => {},
    now = () => Date.now(),
    maxOutboxEntries = DEFAULT_MAX_OUTBOX_ENTRIES,
    maxAttempts = DEFAULT_MAX_ATTEMPTS,
    retryBaseMs = DEFAULT_RETRY_BASE_MS,
    retryMaxMs = DEFAULT_RETRY_MAX_MS,
  } = {}) {
    this.provider = provider;
    this.log = log;
    this.now = now;
    this.maxOutboxEntries = maxOutboxEntries;
    this.maxAttempts = maxAttempts;
    this.retryBaseMs = retryBaseMs;
    this.retryMaxMs = retryMaxMs;
    this.store = null;
    this.timer = null;
    this.inFlight = new Set();
    this.activeSweeps = new Set();
    this.activeNotifications = new Set();
  }

  get available() {
    return Boolean(this.provider && typeof this.provider.send === 'function');
  }

  start({ store, intervalMs = 10_000 }) {
    this.store = store;
    if (Number.isFinite(intervalMs) && intervalMs > 0) {
      this.timer = setInterval(() => {
        const sweep = this.drainDue().catch((error) => {
          this.log('push: outbox sweep failed', error?.code ?? error?.message ?? 'unknown');
        });
        this.activeSweeps.add(sweep);
        void sweep.finally(() => this.activeSweeps.delete(sweep));
      }, intervalMs);
      this.timer.unref?.();
    }
    const initial = this.drainDue().catch((error) => {
      this.log('push: startup outbox sweep failed', error?.code ?? error?.message ?? 'unknown');
    });
    this.activeSweeps.add(initial);
    void initial.finally(() => this.activeSweeps.delete(initial));
  }

  async close() {
    clearInterval(this.timer);
    this.timer = null;
    await Promise.allSettled([...this.activeSweeps, ...this.activeNotifications]);
  }

  register({
    store,
    couple,
    memberId,
    deviceId,
    apnsToken,
    environment,
    bundleId,
    language,
  }) {
    const devices = devicesOf(couple);
    let device = devices.find(
      (candidate) => candidate.memberId === memberId && candidate.deviceId === deviceId,
    );
    // Re-pairing a physical device or APNs rotating/reusing a token must not
    // leave an old member registration that still receives private alerts.
    for (const candidate of [...devices]) {
      if (candidate === device) continue;
      if (candidate.deviceId === deviceId || candidate.apnsToken === apnsToken) {
        devices.splice(devices.indexOf(candidate), 1);
      }
    }
    if (!device) {
      device = {
        id: id('push'),
        memberId,
        deviceId,
        createdAt: nowIso(),
      };
      devices.push(device);
    }
    Object.assign(device, {
      apnsToken,
      environment,
      bundleId,
      language,
      updatedAt: nowIso(),
      disabledAt: null,
    });

    const mine = devices
      .filter((candidate) => candidate.memberId === memberId)
      .sort((left, right) => left.updatedAt.localeCompare(right.updatedAt));
    for (const old of mine.slice(0, Math.max(0, mine.length - MAX_DEVICES_PER_MEMBER))) {
      devices.splice(devices.indexOf(old), 1);
    }
    store.markDirty();
    return this.view(device);
  }

  unregister({ store, couple, memberId, registrationId }) {
    const devices = devicesOf(couple);
    const index = devices.findIndex(
      (candidate) => candidate.id === registrationId && candidate.memberId === memberId,
    );
    if (index === -1) return false;
    devices.splice(index, 1);
    store.markDirty();
    return true;
  }

  unregisterDevice({ store, couple, memberId, deviceId }) {
    const devices = devicesOf(couple);
    const before = devices.length;
    couple.pushDevices = devices.filter(
      (candidate) => candidate.memberId !== memberId || candidate.deviceId !== deviceId,
    );
    if (couple.pushDevices.length === before) return false;
    store.markDirty();
    return true;
  }

  registrations(couple, memberId) {
    return devicesOf(couple)
      .filter((device) => device.memberId === memberId)
      .map((device) => this.view(device));
  }

  view(device) {
    return {
      id: device.id,
      deviceId: device.deviceId,
      environment: device.environment,
      bundleId: device.bundleId,
      language: device.language,
      createdAt: device.createdAt,
      updatedAt: device.updatedAt,
      disabledAt: device.disabledAt ?? null,
    };
  }

  async notifyPartner({ store, couple, senderMemberId, type, title, body, link }) {
    const targets = devicesOf(couple).filter(
      (device) => device.memberId !== senderMemberId && !device.disabledAt,
    );
    return this.#trackedNotification({ store, couple, targets, type, title, body, link });
  }

  /**
   * Every registered device of ONE specific member — used by the turn push
   * when an extra move keeps the turn with the mover (sync contract c).
   */
  async notifyMember({ store, couple, memberId, type, title, body, link }) {
    const targets = devicesOf(couple).filter(
      (device) => device.memberId === memberId && !device.disabledAt,
    );
    return this.#trackedNotification({ store, couple, targets, type, title, body, link });
  }

  /**
   * Server-initiated moments without a sender (e.g. the Sunday-evening
   * "your week is ready" arrival): every registered device of BOTH members.
   */
  async notifyCouple({ store, couple, type, title, body, link }) {
    const targets = devicesOf(couple).filter((device) => !device.disabledAt);
    return this.#trackedNotification({ store, couple, targets, type, title, body, link });
  }

  async #trackedNotification(request) {
    const notification = this.#enqueueAndDeliver(request);
    this.activeNotifications.add(notification);
    try {
      return await notification;
    } finally {
      this.activeNotifications.delete(notification);
    }
  }

  async #enqueueAndDeliver({ store, couple, targets, type, title, body, link }) {
    if (!this.available || targets.length === 0) {
      return { delivered: 0, failed: 0, gated: !this.available, targets: targets.length };
    }

    const outbox = outboxOf(couple);
    const entries = [];
    for (const target of targets) {
      if (!this.#makeOutboxRoom(outbox)) {
        this.log('push: outbox full; notification not queued', couple.id, target.id);
        continue;
      }
      const createdAt = new Date(this.now()).toISOString();
      const entry = {
        id: id('push_delivery'),
        idempotencyKey: randomUUID(),
        targetRegistrationId: target.id,
        payload: {
          aps: {
            alert: {
              title: String(localized(title, target.language)).slice(0, MAX_ALERT_TITLE),
              body: String(localized(body, target.language)).slice(0, MAX_ALERT_BODY),
            },
            sound: 'default',
            'thread-id': `sooodreamy-${couple.id}`,
          },
          type,
          link,
        },
        status: 'pending',
        attempts: 0,
        createdAt,
        nextAttemptAt: createdAt,
        lastAttemptAt: null,
        lastError: null,
        deliveredAt: null,
        deadLetterAt: null,
      };
      outbox.push(entry);
      entries.push(entry);
    }
    if (entries.length > 0) store.markDirty();

    const results = await Promise.all(entries.map((entry) =>
      this.#deliverEntry(store, couple, entry)));
    const delivered = results.filter((result) => result === 'delivered').length;
    const failed = entries.length - delivered;
    return {
      delivered,
      failed,
      gated: false,
      targets: targets.length,
      queued: entries.length,
    };
  }

  #makeOutboxRoom(outbox) {
    while (outbox.length >= this.maxOutboxEntries) {
      const terminalIndex = outbox.findIndex((entry) =>
        entry.status === 'delivered' || entry.status === 'dead_letter');
      if (terminalIndex === -1) return false;
      outbox.splice(terminalIndex, 1);
    }
    return true;
  }

  async drainDue(nowMs = this.now()) {
    if (!this.available || !this.store) return 0;
    const due = [];
    for (const couple of Object.values(this.store.data.couples ?? {})) {
      for (const entry of outboxOf(couple)) {
        if (entry.status !== 'pending' || Date.parse(entry.nextAttemptAt) > nowMs) continue;
        due.push({ couple, entry });
        if (due.length >= MAX_DELIVERIES_PER_SWEEP) break;
      }
      if (due.length >= MAX_DELIVERIES_PER_SWEEP) break;
    }
    let attempted = 0;
    for (const { couple, entry } of due) {
      const result = await this.#deliverEntry(this.store, couple, entry);
      if (result !== 'in_flight') attempted += 1;
    }
    return attempted;
  }

  async #deliverEntry(store, couple, entry) {
    if (this.inFlight.has(entry.id)) return 'in_flight';
    if (!this.available) return 'gated';
    this.inFlight.add(entry.id);
    try {
      const target = devicesOf(couple).find(
        (device) => device.id === entry.targetRegistrationId && !device.disabledAt,
      );
      if (!target) {
        this.#deadLetter(store, entry, 'registration_missing');
        return 'dead_letter';
      }
      entry.attempts += 1;
      entry.lastAttemptAt = new Date(this.now()).toISOString();
      store.markDirty();
      try {
        await this.provider.send({
          token: target.apnsToken,
          environment: target.environment,
          bundleId: target.bundleId,
          payload: entry.payload,
          idempotencyKey: entry.idempotencyKey,
        });
        entry.status = 'delivered';
        entry.deliveredAt = new Date(this.now()).toISOString();
        entry.nextAttemptAt = null;
        entry.lastError = null;
        store.markDirty();
        return 'delivered';
      } catch (error) {
        const reason = String(error?.code ?? error?.message ?? 'unknown').slice(0, 160);
        entry.lastError = reason;
        if (error?.permanent === true) {
          target.disabledAt = nowIso();
          this.#deadLetter(store, entry, reason);
          return 'dead_letter';
        }
        if (entry.attempts >= this.maxAttempts) {
          this.#deadLetter(store, entry, reason);
          return 'dead_letter';
        }
        const delayMs = Math.min(
          this.retryMaxMs,
          this.retryBaseMs * (2 ** Math.max(0, entry.attempts - 1)),
        );
        entry.nextAttemptAt = new Date(this.now() + delayMs).toISOString();
        store.markDirty();
        this.log('push: delivery failed; retry scheduled', reason);
        return 'pending';
      }
    } finally {
      this.inFlight.delete(entry.id);
    }
  }

  #deadLetter(store, entry, reason) {
    entry.status = 'dead_letter';
    entry.deadLetterAt = new Date(this.now()).toISOString();
    entry.nextAttemptAt = null;
    entry.lastError = reason;
    store.markDirty();
    this.log('push: delivery dead-lettered', reason);
  }
}

