import { test } from 'node:test'
import assert from 'node:assert/strict'
import { hashPassword, verifyPassword, randomToken, sha256 } from '../../src/lib/passwords.ts'

test('hash + verify roundtrip', () => {
  const hash = hashPassword('correct horse battery staple')
  assert.ok(verifyPassword('correct horse battery staple', hash))
  assert.ok(!verifyPassword('wrong password', hash))
})

test('same password hashes differently (salted)', () => {
  const a = hashPassword('hunter22')
  const b = hashPassword('hunter22')
  assert.notEqual(a, b)
  assert.ok(verifyPassword('hunter22', a))
  assert.ok(verifyPassword('hunter22', b))
})

test('verify tolerates malformed stored values', () => {
  assert.ok(!verifyPassword('x', 'not-a-hash'))
  assert.ok(!verifyPassword('x', ''))
  assert.ok(!verifyPassword('x', 'a:b:c:d'))
})

test('randomToken length and uniqueness', () => {
  const token = randomToken()
  assert.equal(token.length, 64) // 32 bytes hex
  assert.notEqual(token, randomToken())
})

test('sha256 is deterministic', () => {
  assert.equal(sha256('abc'), sha256('abc'))
  assert.notEqual(sha256('abc'), sha256('abd'))
})
