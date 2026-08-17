import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { Store } from '../../src/lib/jsonstore.ts'
import { AuthService } from '../../src/auth/service.ts'
import { generateTotpSecret, totpCode } from '../../src/lib/totp.ts'
import type { User } from '../../src/types.ts'

const CODE_RE = /^[a-km-np-z2-9]{4}-[a-km-np-z2-9]{4}-[a-km-np-z2-9]{4}$/

function makeAuth(): { auth: AuthService; dir: string } {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-recovery-'))
  return { auth: new AuthService(new Store(dir), 14), dir }
}

function makeTotpUser(auth: AuthService, username = 'alice'): { user: User; secret: string } {
  const { user } = auth.createUser(username, 'password-123', 'user')
  assert.ok(user)
  const secret = generateTotpSecret()
  auth.users.update(user.id, { totpSecret: secret, totpEnabled: true })
  return { user: auth.users.get(user.id)!, secret }
}

test('generateRecoveryCodes: format, uniqueness, only hashes stored', () => {
  const { auth, dir } = makeAuth()
  const { user } = makeTotpUser(auth)

  const codes = auth.generateRecoveryCodes(user.id)
  assert.equal(codes.length, 10)
  for (const code of codes) {
    assert.match(code, CODE_RE)
    // No ambiguous characters ever appear
    assert.doesNotMatch(code, /[01ol]/)
  }
  assert.equal(new Set(codes).size, 10, 'codes are unique')

  const stored = auth.users.get(user.id)!.recoveryCodes ?? []
  assert.equal(stored.length, 10)
  assert.equal(auth.recoveryCodesRemaining(auth.users.get(user.id)!), 10)
  for (const hash of stored) {
    assert.match(hash, /^[0-9a-f]{64}$/, 'stored values are sha256 hex digests')
    assert.ok(!codes.includes(hash), 'plaintext codes are never persisted')
  }

  // Regenerating replaces the whole set
  const next = auth.generateRecoveryCodes(user.id)
  const replaced = auth.users.get(user.id)!.recoveryCodes ?? []
  assert.equal(replaced.length, 10)
  assert.equal(next.length, 10)
  for (const hash of replaced) assert.ok(!stored.includes(hash), 'old hashes are gone after regeneration')

  fs.rmSync(dir, { recursive: true, force: true })
})

test('login accepts a recovery code exactly once, TOTP keeps working', () => {
  const { auth, dir } = makeAuth()
  const { user, secret } = makeTotpUser(auth)
  const codes = auth.generateRecoveryCodes(user.id)

  // Password alone: 2FA challenge
  assert.equal(auth.login('alice', 'password-123').totpRequired, true)

  // Recovery code in place of the TOTP code
  const first = auth.login('alice', 'password-123', codes[0])
  assert.ok(first.user, 'recovery code accepted')
  assert.equal(auth.recoveryCodesRemaining(auth.users.get(user.id)!), 9)

  // Single-use: the same code must not work twice
  const replay = auth.login('alice', 'password-123', codes[0])
  assert.equal(replay.user, undefined)
  assert.deepEqual(replay.problems, ['invalid 2FA code'])
  assert.equal(auth.recoveryCodesRemaining(auth.users.get(user.id)!), 9)

  // Case-insensitive, dashes optional, surrounding whitespace tolerated
  const messy = `  ${codes[1].toUpperCase().replaceAll('-', '')} `
  assert.ok(auth.login('alice', 'password-123', messy).user, 'normalized recovery code accepted')
  assert.equal(auth.recoveryCodesRemaining(auth.users.get(user.id)!), 8)

  // A wrong password is never rescued by a valid recovery code (and does not consume it)
  const badPw = auth.login('alice', 'wrong-password', codes[2])
  assert.equal(badPw.user, undefined)
  assert.equal(auth.recoveryCodesRemaining(auth.users.get(user.id)!), 8)

  // Regular TOTP codes still work after recovery use
  assert.ok(auth.login('alice', 'password-123', totpCode(secret)).user, 'TOTP still accepted')

  // Garbage input fails
  assert.equal(auth.login('alice', 'password-123', 'not-a-real-code').user, undefined)

  fs.rmSync(dir, { recursive: true, force: true })
})

test('recovery codes are inert while 2FA is disabled', () => {
  const { auth, dir } = makeAuth()
  const { user } = makeTotpUser(auth, 'bob')
  const codes = auth.generateRecoveryCodes(user.id)

  // Simulate stale hashes surviving a 2FA disable
  auth.users.update(user.id, { totpEnabled: false, totpSecret: null })

  // Password alone signs in — no 2FA challenge
  assert.ok(auth.login('bob', 'password-123').user)

  // Passing a recovery code must not hit the redemption path: nothing is consumed
  assert.ok(auth.login('bob', 'password-123', codes[0]).user)
  assert.equal(auth.recoveryCodesRemaining(auth.users.get(user.id)!), 10)

  // And a recovery code never replaces the password
  assert.equal(auth.login('bob', codes[0]).user, undefined)

  fs.rmSync(dir, { recursive: true, force: true })
})
