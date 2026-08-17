import { test } from 'node:test'
import assert from 'node:assert/strict'
import { base32Decode, base32Encode, generateTotpSecret, totpCode, verifyTotp, otpauthUri } from '../../src/lib/totp.ts'

// RFC 6238 SHA-1 test secret: ASCII "12345678901234567890"
const RFC_SECRET_B32 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'

test('base32 roundtrip', () => {
  const buf = Buffer.from('12345678901234567890', 'ascii')
  const encoded = base32Encode(buf)
  assert.equal(encoded, RFC_SECRET_B32)
  assert.deepEqual(base32Decode(encoded), buf)
})

test('RFC 6238 test vectors (6-digit truncation of SHA-1 vectors)', () => {
  // 8-digit reference values 94287082 / 07081804 / 14050471 → last 6 digits
  assert.equal(totpCode(RFC_SECRET_B32, 59 * 1000), '287082')
  assert.equal(totpCode(RFC_SECRET_B32, 1111111109 * 1000), '081804')
  assert.equal(totpCode(RFC_SECRET_B32, 1111111111 * 1000), '050471')
})

test('verify accepts ±1 step drift and rejects others', () => {
  const at = 1111111109 * 1000
  const code = totpCode(RFC_SECRET_B32, at)
  assert.ok(verifyTotp(RFC_SECRET_B32, code, at))
  assert.ok(verifyTotp(RFC_SECRET_B32, code, at + 30_000)) // one step later
  assert.ok(!verifyTotp(RFC_SECRET_B32, code, at + 90_000)) // three steps later
  assert.ok(!verifyTotp(RFC_SECRET_B32, '000000', at))
})

test('generated secrets are unique and decodable', () => {
  const a = generateTotpSecret()
  const b = generateTotpSecret()
  assert.notEqual(a, b)
  assert.equal(base32Decode(a).length, 20)
})

test('otpauth URI encodes issuer and account', () => {
  const uri = otpauthUri(RFC_SECRET_B32, 'admin', 'My Panel')
  assert.ok(uri.startsWith('otpauth://totp/My%20Panel:admin?secret='))
  assert.ok(uri.includes('issuer=My%20Panel'))
})
