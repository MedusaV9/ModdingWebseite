import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseEnvelope, buildMsg, buildError, sanitizeName, PROTO_V } from '../src/protocol.js';
import { loadConfig, dayKey, monthKey } from '../src/config.js';

test('Envelope: gültige Message parst', () => {
  const r = parseEnvelope(JSON.stringify({ v: 1, t: 'HELLO', seq: 1, ts: 5, d: { a: 1 } }));
  assert.equal(r.ok, true);
  assert.equal(r.msg.t, 'HELLO');
  assert.deepEqual(r.msg.d, { a: 1 });
});

test('Envelope: fehlendes d wird zu {}', () => {
  const r = parseEnvelope(JSON.stringify({ v: 1, t: 'PING', seq: 2 }));
  assert.equal(r.ok, true);
  assert.deepEqual(r.msg.d, {});
});

test('Envelope: v-Check lehnt fremde Versionen ab (mit close)', () => {
  for (const v of [0, 2, '1', null, undefined]) {
    const r = parseEnvelope(JSON.stringify({ v, t: 'HELLO', d: {} }));
    assert.equal(r.ok, false);
    assert.equal(r.code, 'PROTO_VERSION');
    assert.equal(r.close, true);
  }
});

test('Envelope: kaputtes JSON / falsche Typen → BAD_MESSAGE', () => {
  assert.equal(parseEnvelope('{oops').code, 'BAD_MESSAGE');
  assert.equal(parseEnvelope('[1,2]').code, 'BAD_MESSAGE');
  assert.equal(parseEnvelope(JSON.stringify({ v: 1, t: 'kleinbuchstaben', d: {} })).code, 'BAD_MESSAGE');
  assert.equal(parseEnvelope(JSON.stringify({ v: 1, t: 'X', seq: -1, d: {} })).code, 'BAD_MESSAGE');
  assert.equal(parseEnvelope(JSON.stringify({ v: 1, t: 'X', d: [1] })).code, 'BAD_MESSAGE');
});

test('Envelope: Größenlimit greift', () => {
  const big = JSON.stringify({ v: 1, t: 'X', d: { pad: 'x'.repeat(20_000) } });
  assert.equal(parseEnvelope(big, 16 * 1024).code, 'PAYLOAD_TOO_LARGE');
});

test('buildMsg/buildError: Envelope-Felder + re-Korrelation', () => {
  const msg = JSON.parse(buildMsg('WELCOME', { x: 1 }, { re: 7 }));
  assert.equal(msg.v, PROTO_V);
  assert.equal(msg.t, 'WELCOME');
  assert.equal(msg.re, 7);
  assert.equal(typeof msg.ts, 'number');
  assert.deepEqual(msg.d, { x: 1 });
  const err = JSON.parse(buildError('RATE_LIMIT', { re: 3, message: 'langsam' }));
  assert.equal(err.t, 'ERROR');
  assert.equal(err.d.code, 'RATE_LIMIT');
  assert.equal(err.re, 3);
});

test('sanitizeName: Steuerzeichen raus, Länge gedeckelt, leer → null', () => {
  assert.equal(sanitizeName('  Herr\u0000Flauschig\n '), 'HerrFlauschig');
  assert.equal(sanitizeName('x'.repeat(50), 24).length, 24);
  assert.equal(sanitizeName('\u0001\u0002'), null);
  assert.equal(sanitizeName(42), null);
});

test('Config: Defaults (PORT 8080, DATA_DIR ./data, Panel aus ohne Passwort)', () => {
  const cfg = loadConfig({});
  assert.equal(cfg.port, 8080);
  assert.equal(cfg.dataDir, './data');
  assert.equal(cfg.adminPassword, null);
  assert.equal(cfg.palDailyLimit, 250);
  assert.equal(cfg.tz, 'Europe/Berlin');
});

test('Config: ENV überschreibt (inkl. GOOBY_DATA_DIR-Alias)', () => {
  const cfg = loadConfig({ PORT: '9000', GOOBY_DATA_DIR: '/tmp/x', GOOBY_PAL_DAILY_LIMIT: '100' });
  assert.equal(cfg.port, 9000);
  assert.equal(cfg.dataDir, '/tmp/x');
  assert.equal(cfg.palDailyLimit, 100);
});

test('dayKey: Zeitzonen-korrekt (Berlin vs UTC um Mitternacht)', () => {
  // 2026-07-24 23:30 UTC = 2026-07-25 01:30 Berlin (Sommerzeit).
  const ts = Date.UTC(2026, 6, 24, 23, 30);
  assert.equal(dayKey(ts, 'UTC'), '2026-07-24');
  assert.equal(dayKey(ts, 'Europe/Berlin'), '2026-07-25');
  assert.equal(monthKey(ts, 'Europe/Berlin'), '2026-07');
});
