// Message-Envelope {v,t,seq,ts,d} — Doc C §1.1. Parse/Build + Basis-Validierung.

export const PROTO_V = 1;
const TYPE_RE = /^[A-Z][A-Z0-9_]{0,39}$/;

// parseEnvelope(raw, maxBytes) → { ok:true, msg } | { ok:false, code, close? }
export function parseEnvelope(raw, maxBytes = 16 * 1024) {
  const text = typeof raw === 'string' ? raw : raw.toString('utf8');
  if (Buffer.byteLength(text, 'utf8') > maxBytes) {
    return { ok: false, code: 'PAYLOAD_TOO_LARGE' };
  }
  let msg;
  try {
    msg = JSON.parse(text);
  } catch {
    return { ok: false, code: 'BAD_MESSAGE' };
  }
  if (typeof msg !== 'object' || msg === null || Array.isArray(msg)) {
    return { ok: false, code: 'BAD_MESSAGE' };
  }
  if (msg.v !== PROTO_V) return { ok: false, code: 'PROTO_VERSION', close: true };
  if (typeof msg.t !== 'string' || !TYPE_RE.test(msg.t)) {
    return { ok: false, code: 'BAD_MESSAGE' };
  }
  if (msg.seq !== undefined && (!Number.isInteger(msg.seq) || msg.seq < 0)) {
    return { ok: false, code: 'BAD_MESSAGE' };
  }
  if (msg.d === undefined || msg.d === null) msg.d = {};
  if (typeof msg.d !== 'object' || Array.isArray(msg.d)) {
    return { ok: false, code: 'BAD_MESSAGE' };
  }
  return { ok: true, msg };
}

// buildMsg("WELCOME", {...}, {re: 1}) → JSON-String, versandfertig.
export function buildMsg(t, d = {}, { re, seq } = {}) {
  const msg = { v: PROTO_V, t, ts: Date.now() };
  if (re !== undefined) msg.re = re;
  if (seq !== undefined) msg.seq = seq;
  msg.d = d;
  return JSON.stringify(msg);
}

export function buildError(code, { re, message } = {}) {
  const d = { code };
  if (message) d.message = message;
  return buildMsg('ERROR', d, { re });
}

// Namen (Spieler/Gooby): Steuerzeichen raus, trimmen, Länge deckeln. Kein HTML nötig —
// das Panel escaped beim Rendern (defense in depth).
export function sanitizeName(value, maxLen = 24) {
  if (typeof value !== 'string') return null;
  // eslint-disable-next-line no-control-regex
  const clean = value.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, maxLen);
  return clean.length > 0 ? clean : null;
}
