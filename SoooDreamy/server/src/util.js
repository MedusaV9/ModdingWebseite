import crypto from 'node:crypto';

const DAY_MS = 86_400_000;
const DATE_KEY_RE = /^\d{4}-\d{2}-\d{2}$/;
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export class HttpError extends Error {
  constructor(status, code, message) {
    super(message ?? code);
    this.status = status;
    this.code = code;
  }
}

export function httpError(status, code, message) {
  return new HttpError(status, code, message);
}

export function id(prefix) {
  return `${prefix}_${crypto.randomBytes(8).toString('hex')}`;
}

export function newToken() {
  return `tok_${crypto.randomBytes(24).toString('hex')}`;
}

export function newCoupleCode() {
  let code = '';
  for (let i = 0; i < 6; i++) code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  return code;
}

export function nowIso() {
  return new Date().toISOString();
}

export function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

export function prevDateKey(dateKey) {
  return new Date(Date.parse(`${dateKey}T00:00:00.000Z`) - DAY_MS).toISOString().slice(0, 10);
}

export function nextDateKey(dateKey) {
  return new Date(Date.parse(`${dateKey}T00:00:00.000Z`) + DAY_MS).toISOString().slice(0, 10);
}

export function isValidDateKey(value) {
  return (
    typeof value === 'string' &&
    DATE_KEY_RE.test(value) &&
    Number.isFinite(Date.parse(`${value}T00:00:00.000Z`))
  );
}

export function daysBetween(dateKey, now = Date.now()) {
  const start = Date.parse(`${dateKey}T00:00:00.000Z`);
  if (!Number.isFinite(start)) return 0;
  return Math.max(0, Math.floor((now - start) / DAY_MS));
}

export function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

/**
 * Reads a request body up to `limit` bytes. If the body is larger the rest is
 * drained (so keep-alive clients get a clean 413 response) and a 413 HttpError
 * is thrown. Bodies that exceed the limit by more than 64 MB abort the socket.
 */
export function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length']);
    let tooLarge = Number.isFinite(declared) && declared > limit;
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (!tooLarge && size > limit) {
        tooLarge = true;
        chunks.length = 0;
      }
      if (tooLarge) {
        if (size > limit + 64 * 1024 * 1024) req.destroy(new Error('body far exceeds limit'));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (tooLarge) reject(httpError(413, 'too_large', `Request body exceeds ${limit} bytes`));
      else resolve(Buffer.concat(chunks));
    });
    req.on('error', (err) =>
      reject(err instanceof HttpError ? err : httpError(400, 'bad_request', 'Could not read request body')),
    );
  });
}

export async function readJsonObject(req, limit = 1024 * 1024) {
  const buf = await readBody(req, limit);
  if (buf.length === 0) throw httpError(400, 'invalid_json', 'Expected a JSON body');
  let parsed;
  try {
    parsed = JSON.parse(buf.toString('utf8'));
  } catch {
    throw httpError(400, 'invalid_json', 'Body is not valid JSON');
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw httpError(400, 'invalid_request', 'Body must be a JSON object');
  }
  return parsed;
}
