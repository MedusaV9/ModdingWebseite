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
  // Ranch-MP (RANCH-DLC-IDEAS-4 §1.1/§2.4): eigener, schnellerer Pose-Kanal —
  // 12/s (10 Hz + Ereignis-Posen bei Sprung/Landung), Burst 20; Fangen darf
  // kurz auf 15 Hz gehen und lebt vom Burst. Events deutlich niedriger.
  mgPose: { capacity: 20, refillPerSec: 12 }, // MG_POSE pro Verbindung+Room
  mgEvent: { capacity: 12, refillPerSec: 4 }, // MG_EVENT (Checkpoint/Tag/…) pro Verbindung+Room
  rmpInvite: { capacity: 8, refillPerSec: 8 / 60 }, // Ranch-Einladungen 8/min pro Gerät
  rmpScore: { capacity: 10, refillPerSec: 10 / 60 }, // Score-/Ghost-Upload 10/min pro Gerät
};
