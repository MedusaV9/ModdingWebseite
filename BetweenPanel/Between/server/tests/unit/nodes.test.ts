/**
 * Unit tests for the pure pieces of multi-node support: the constant-time
 * bearer token comparison used by node agents, the Authorization header
 * parsing, and admin-supplied node registration validation.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { bearerToken, tokenEquals, makeNodeAuthMiddleware, NODE_AGENT_USER } from '../../src/nodes/token.ts'
import { validateNodeInput } from '../../src/nodes/service.ts'
import type { AuthedRequest } from '../../src/auth/service.ts'

// --- tokenEquals -------------------------------------------------------------

test('tokenEquals matches identical tokens', () => {
  assert.equal(tokenEquals('super-secret-node-token', 'super-secret-node-token'), true)
})

test('tokenEquals rejects different tokens of the same length', () => {
  assert.equal(tokenEquals('aaaaaaaaaaaaaaaa', 'aaaaaaaaaaaaaaab'), false)
})

test('tokenEquals rejects different lengths without throwing', () => {
  // timingSafeEqual throws on raw length mismatch — the sha256 normalization
  // must absorb that so length can't be probed via exceptions either.
  assert.equal(tokenEquals('short', 'a-much-longer-expected-token'), false)
  assert.equal(tokenEquals('a-much-longer-presented-token', 'short'), false)
})

test('tokenEquals rejects empty expected token (unconfigured agent)', () => {
  assert.equal(tokenEquals('anything', ''), false)
  assert.equal(tokenEquals('', ''), false)
})

test('tokenEquals rejects non-string input defensively', () => {
  assert.equal(tokenEquals(undefined as unknown as string, 'expected-token-value'), false)
  assert.equal(tokenEquals('presented', null as unknown as string), false)
})

// --- bearerToken -------------------------------------------------------------

test('bearerToken extracts the token from a well-formed header', () => {
  assert.equal(bearerToken('Bearer abc123'), 'abc123')
  assert.equal(bearerToken('Bearer   padded-token  '), 'padded-token')
})

test('bearerToken rejects absent or malformed headers', () => {
  assert.equal(bearerToken(undefined), null)
  assert.equal(bearerToken(''), null)
  assert.equal(bearerToken('Basic dXNlcjpwYXNz'), null)
  assert.equal(bearerToken('bearer lowercase-scheme'), null)
  assert.equal(bearerToken('Bearer'), null)
  assert.equal(bearerToken('Bearer '), null)
})

// --- makeNodeAuthMiddleware ---------------------------------------------------

function runMiddleware(authHeader: string | undefined, expected: string): AuthedRequest {
  const req = { headers: { authorization: authHeader } } as AuthedRequest
  let called = false
  makeNodeAuthMiddleware(expected)(req, {} as never, () => (called = true))
  assert.equal(called, true, 'middleware must always call next()')
  return req
}

test('node auth middleware authenticates a matching bearer token as the agent principal', () => {
  const req = runMiddleware('Bearer expected-token-value', 'expected-token-value')
  assert.equal(req.user, NODE_AGENT_USER)
  assert.equal(req.user!.role, 'admin')
})

test('node auth middleware leaves mismatches unauthenticated (requireAuth 401s later)', () => {
  assert.equal(runMiddleware('Bearer wrong-token-value', 'expected-token-value').user, undefined)
  assert.equal(runMiddleware(undefined, 'expected-token-value').user, undefined)
  assert.equal(runMiddleware('Basic abc', 'expected-token-value').user, undefined)
})

// --- validateNodeInput ---------------------------------------------------------

const VALID = { name: 'rack-2', baseUrl: 'http://192.168.1.50:8484', token: 'a'.repeat(24) }

test('validateNodeInput accepts a valid node and normalizes the base URL to its origin', () => {
  const { problems, value } = validateNodeInput({ ...VALID, baseUrl: 'http://192.168.1.50:8484/' })
  assert.deepEqual(problems, [])
  assert.equal(value!.baseUrl, 'http://192.168.1.50:8484')
  assert.equal(value!.name, 'rack-2')
})

test('validateNodeInput allows https and LAN/private hosts by design', () => {
  assert.deepEqual(validateNodeInput({ ...VALID, baseUrl: 'https://node.example.com' }).problems, [])
  assert.deepEqual(validateNodeInput({ ...VALID, baseUrl: 'http://10.0.0.7:9000' }).problems, [])
  assert.deepEqual(validateNodeInput({ ...VALID, baseUrl: 'http://localhost:8485' }).problems, [])
})

test('validateNodeInput rejects bad names', () => {
  assert.ok(validateNodeInput({ ...VALID, name: '' }).problems.length > 0)
  assert.ok(validateNodeInput({ ...VALID, name: 'x'.repeat(61) }).problems.length > 0)
})

test('validateNodeInput rejects short and oversized tokens', () => {
  assert.ok(validateNodeInput({ ...VALID, token: 'short' }).problems.some((p) => p.includes('at least')))
  assert.ok(validateNodeInput({ ...VALID, token: 'a'.repeat(501) }).problems.some((p) => p.includes('too long')))
})

test('validateNodeInput rejects malformed and non-http(s) URLs', () => {
  assert.ok(validateNodeInput({ ...VALID, baseUrl: 'not a url' }).problems.length > 0)
  assert.ok(validateNodeInput({ ...VALID, baseUrl: 'ftp://files.example.com' }).problems.some((p) => p.includes('http')))
  assert.ok(validateNodeInput({ ...VALID, baseUrl: 'file:///etc/passwd' }).problems.some((p) => p.includes('http')))
})

test('validateNodeInput rejects URLs with credentials, query, fragment or path', () => {
  assert.ok(validateNodeInput({ ...VALID, baseUrl: 'http://user:pass@host:1234' }).problems.some((p) => p.includes('credentials')))
  assert.ok(validateNodeInput({ ...VALID, baseUrl: 'http://host:1234?x=1' }).problems.some((p) => p.includes('query')))
  assert.ok(validateNodeInput({ ...VALID, baseUrl: 'http://host:1234#frag' }).problems.some((p) => p.includes('query')))
  assert.ok(validateNodeInput({ ...VALID, baseUrl: 'http://host:1234/agent' }).problems.some((p) => p.includes('path')))
})

test('validateNodeInput tolerates junk input shapes', () => {
  assert.ok(validateNodeInput(null).problems.length > 0)
  assert.ok(validateNodeInput('a string').problems.length > 0)
  assert.ok(validateNodeInput({}).problems.length > 0)
})
