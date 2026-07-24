// Identität & Auth (Doc C §3.1/§7): anonyme Geräte, TOFU-deviceSecret (nur Hash gespeichert),
// FriendCode-Vergabe, REST-Bearer-Check. KEIN PII: nur Spitznamen + zufällige IDs.

import crypto from 'node:crypto';

const DEVICE_ID_RE = /^[A-Za-z0-9._-]{8,64}$/;
const SECRET_RE = /^[0-9a-fA-F]{32,64}$/;
// Base32 ohne I/O/0/1 (Doc C §3.1): 24 Buchstaben + 8 Ziffern = 32 Zeichen.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export function hashSecret(secret) {
  return `sha256:${crypto.createHash('sha256').update(secret).digest('hex')}`;
}

export function validDeviceId(id) {
  return typeof id === 'string' && DEVICE_ID_RE.test(id);
}

export function validSecret(secret) {
  return typeof secret === 'string' && SECRET_RE.test(secret);
}

export function secretMatches(secret, storedHash) {
  const a = Buffer.from(hashSecret(secret));
  const b = Buffer.from(String(storedHash));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// "GOOBY-4K7Q" — kollisionsfrei gegen die players-Collection gewürfelt.
export function newFriendCode(players) {
  const taken = new Set(Object.values(players).map((p) => p.friendCode));
  for (;;) {
    let code = 'GOOBY-';
    const bytes = crypto.randomBytes(4);
    for (let i = 0; i < 4; i++) code += CODE_ALPHABET[bytes[i] % 32];
    if (!taken.has(code)) return code;
  }
}

export const FRIEND_CODE_RE = /^GOOBY-[A-HJ-NP-Z2-9]{4}$/;

// REST: Authorization: Bearer <deviceId>:<deviceSecret> → Player oder null.
// Konstantzeit-Hash-Vergleich; Fehlerdetails absichtlich einheitlich (kein User-Enumeration-Orakel).
export function restAuth(ctx, req) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) return null;
  const idx = header.indexOf(':');
  if (idx < 0) return null;
  const deviceId = header.slice('Bearer '.length, idx).trim();
  const secret = header.slice(idx + 1).trim();
  if (!validDeviceId(deviceId) || !validSecret(secret)) return null;
  const player = ctx.players[deviceId];
  if (!player || player.banned) return null;
  if (!secretMatches(secret, player.secretHash)) return null;
  return { deviceId, player };
}
