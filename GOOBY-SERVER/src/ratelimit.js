// Token-Bucket-Rate-Limits (Doc C §7). In-Memory (keine IP-Persistenz über Session hinaus).
// Deterministisch testbar: now wird injiziert.

export class Buckets {
  constructor(now = () => Date.now()) {
    this.now = now;
    this.map = new Map(); // key -> { tokens, updatedAt }
    this.lastSweep = now();
  }

  // take("hello:1.2.3.4", {capacity:5, refillPerSec:5/60}) → true wenn erlaubt.
  take(key, { capacity, refillPerSec }, cost = 1) {
    const now = this.now();
    this._sweep(now);
    let b = this.map.get(key);
    if (!b) {
      b = { tokens: capacity, updatedAt: now };
      this.map.set(key, b);
    }
    const elapsedSec = Math.max(0, (now - b.updatedAt) / 1000);
    b.tokens = Math.min(capacity, b.tokens + elapsedSec * refillPerSec);
    b.updatedAt = now;
    if (b.tokens >= cost) {
      b.tokens -= cost;
      return true;
    }
    return false;
  }

  // Alte Buckets gelegentlich wegwerfen (Memory-Hygiene bei vielen IP-Keys).
  _sweep(now) {
    if (now - this.lastSweep < 10 * 60_000) return;
    this.lastSweep = now;
    for (const [key, b] of this.map) {
      if (now - b.updatedAt > 60 * 60_000) this.map.delete(key);
    }
  }
}

// Zentrale Limit-Presets (Doc C §7) — eine Stelle, damit Tests + Module übereinstimmen.
export const LIMITS = {
  wsMsg: { capacity: 60, refillPerSec: 30 }, // 30 msg/s, Burst 60, pro Verbindung
  hello: { capacity: 5, refillPerSec: 5 / 60 }, // 5/min pro IP
  friendRequest: { capacity: 10, refillPerSec: 10 / 3600 }, // 10/h pro Gerät
  palSend: { capacity: 20, refillPerSec: 20 / 3600 }, // 20/h pro Gerät
  codesRedeem: { capacity: 5, refillPerSec: 5 / 900 }, // 5/15min pro Gerät
  panelLogin: { capacity: 5, refillPerSec: 5 / 900 }, // 5/15min pro IP
  presenceSet: { capacity: 12, refillPerSec: 12 / 60 }, // 12/min pro Gerät
  roomPos: { capacity: 10, refillPerSec: 5 }, // POS-Relay 5 Hz (Burst 10) pro Verbindung+Room
};
