import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { AuthService } from '../../src/auth/service.ts'
import { Store } from '../../src/lib/jsonstore.ts'

test('login rate-limit state is bounded and reclaims expired windows', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-auth-limits-'))
  const auth = new AuthService(new Store(dir), 7)
  const attempts = (auth as unknown as { loginAttempts: Map<string, unknown> }).loginAttempts
  const originalNow = Date.now
  let now = originalNow()
  Date.now = () => now
  try {
    for (let i = 0; i < 10_000; i++) assert.equal(auth.rateLimitLogin(`198.51.${i >>> 8}.${i & 255}`), true)
    assert.equal(attempts.size, 10_000)
    assert.equal(auth.rateLimitLogin('203.0.113.1'), false, 'new addresses fail closed at the cap')
    assert.equal(attempts.size, 10_000)

    now += 5 * 60 * 1000 + 1
    assert.equal(auth.rateLimitLogin('203.0.113.1'), true, 'expired windows are reclaimed')
    assert.equal(attempts.size, 1)
  } finally {
    Date.now = originalNow
    fs.rmSync(dir, { recursive: true, force: true })
  }
})
