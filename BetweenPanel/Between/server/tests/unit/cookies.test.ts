import { test } from 'node:test'
import assert from 'node:assert/strict'
import { parseCookies } from '../../src/auth/service.ts'

test('parseCookies parses a simple cookie header', () => {
  const out = parseCookies('between_session=abc123; theme=dark')
  assert.equal(out['between_session'], 'abc123')
  assert.equal(out['theme'], 'dark')
})

test('parseCookies decodes percent-escapes', () => {
  const out = parseCookies('name=hello%20world')
  assert.equal(out['name'], 'hello world')
})

test('parseCookies never throws on malformed percent-escapes', () => {
  // "%zz" is an invalid escape — decodeURIComponent would throw URIError.
  // This used to crash the whole panel via the WS upgrade path.
  const out = parseCookies('between_session=%zz%bad; ok=1')
  assert.equal(out['between_session'], '%zz%bad') // falls back to raw value
  assert.equal(out['ok'], '1')
})

test('parseCookies handles empty/undefined headers', () => {
  assert.deepEqual(parseCookies(undefined), {})
  assert.deepEqual(parseCookies(''), {})
})

test('parseCookies skips parts without equals sign', () => {
  const out = parseCookies('garbage; a=1')
  assert.equal(out['a'], '1')
  assert.ok(!('garbage' in out))
})

test('parseCookies trims whitespace around names and values', () => {
  const out = parseCookies('  spaced  =  value  ; b=2')
  assert.equal(out['spaced'], 'value')
  assert.equal(out['b'], '2')
})
