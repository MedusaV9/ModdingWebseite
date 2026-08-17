/**
 * Password hashing with Node's built-in scrypt (no external deps).
 * Format: scrypt:N:r:p:saltB64:hashB64
 */
import crypto from 'node:crypto'

const N = 16384
const R = 8
const P = 1
const KEYLEN = 64

export function hashPassword(password: string): string {
  const salt = crypto.randomBytes(16)
  const hash = crypto.scryptSync(password, salt, KEYLEN, { N, r: R, p: P })
  return `scrypt:${N}:${R}:${P}:${salt.toString('base64')}:${hash.toString('base64')}`
}

export function verifyPassword(password: string, stored: string): boolean {
  try {
    const parts = stored.split(':')
    if (parts.length !== 6 || parts[0] !== 'scrypt') return false
    const [, nStr, rStr, pStr, saltB64, hashB64] = parts
    const salt = Buffer.from(saltB64, 'base64')
    const expected = Buffer.from(hashB64, 'base64')
    const actual = crypto.scryptSync(password, salt, expected.length, {
      N: parseInt(nStr, 10),
      r: parseInt(rStr, 10),
      p: parseInt(pStr, 10),
    })
    return crypto.timingSafeEqual(actual, expected)
  } catch {
    return false
  }
}

export function randomToken(bytes = 32): string {
  return crypto.randomBytes(bytes).toString('hex')
}

export function sha256(input: string): string {
  return crypto.createHash('sha256').update(input).digest('hex')
}
