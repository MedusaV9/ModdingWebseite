/**
 * RFC 6238 TOTP (time-based one-time passwords) — hand-rolled on node:crypto.
 * Used for optional two-factor authentication.
 */
import crypto from 'node:crypto'

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'

export function base32Encode(buf: Buffer): string {
  let bits = 0
  let value = 0
  let output = ''
  for (const byte of buf) {
    value = (value << 8) | byte
    bits += 8
    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31]
      bits -= 5
    }
  }
  if (bits > 0) output += BASE32_ALPHABET[(value << (5 - bits)) & 31]
  return output
}

export function base32Decode(str: string): Buffer {
  const clean = str.toUpperCase().replace(/[^A-Z2-7]/g, '')
  let bits = 0
  let value = 0
  const out: number[] = []
  for (const ch of clean) {
    value = (value << 5) | BASE32_ALPHABET.indexOf(ch)
    bits += 5
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff)
      bits -= 8
    }
  }
  return Buffer.from(out)
}

export function generateTotpSecret(): string {
  return base32Encode(crypto.randomBytes(20))
}

function hotp(secretB32: string, counter: number, digits = 6): string {
  const key = base32Decode(secretB32)
  const msg = Buffer.alloc(8)
  msg.writeBigUInt64BE(BigInt(counter))
  const hmac = crypto.createHmac('sha1', key).update(msg).digest()
  const offset = hmac[hmac.length - 1] & 0x0f
  const code =
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff)
  return String(code % 10 ** digits).padStart(digits, '0')
}

export function totpCode(secretB32: string, atMs = Date.now(), stepS = 30): string {
  return hotp(secretB32, Math.floor(atMs / 1000 / stepS))
}

/** Verify with a ±1 step window to tolerate clock drift. */
export function verifyTotp(secretB32: string, code: string, atMs = Date.now(), stepS = 30): boolean {
  const counter = Math.floor(atMs / 1000 / stepS)
  const normalized = code.replace(/\s+/g, '')
  for (const c of [counter, counter - 1, counter + 1]) {
    if (hotp(secretB32, c) === normalized) return true
  }
  return false
}

export function otpauthUri(secretB32: string, account: string, issuer = 'Between'): string {
  const enc = encodeURIComponent
  return `otpauth://totp/${enc(issuer)}:${enc(account)}?secret=${secretB32}&issuer=${enc(issuer)}&algorithm=SHA1&digits=6&period=30`
}
