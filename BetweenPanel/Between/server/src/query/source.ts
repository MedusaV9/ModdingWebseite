/**
 * Valve Source A2S_INFO and A2S_PLAYER queries (UDP), with S2C_CHALLENGE handling.
 * https://developer.valvesoftware.com/wiki/Server_queries
 */
import dgram from 'node:dgram'
import type { QueryResult } from '../types.ts'

const A2S_INFO = Buffer.concat([
  Buffer.from([0xff, 0xff, 0xff, 0xff, 0x54]),
  Buffer.from('Source Engine Query\0', 'ascii'),
])

export function parseA2sInfo(msg: Buffer, started: number): QueryResult | null {
  if (msg.length < 6 || msg.readInt32LE(0) !== -1) return null
  const type = msg[4]
  if (type !== 0x49) return null // 'I'
  let p = 5
  p += 1 // protocol
  const readStr = () => {
    const end = msg.indexOf(0, p)
    const s = msg.subarray(p, end < 0 ? msg.length : end).toString('utf8')
    p = (end < 0 ? msg.length : end) + 1
    return s
  }
  const name = readStr()
  readStr() // map
  readStr() // folder
  readStr() // game
  p += 2 // appid
  const players = msg[p++] ?? 0
  const maxPlayers = msg[p++] ?? 0
  return {
    online: true,
    playersOnline: players,
    playersMax: maxPlayers,
    motd: name.slice(0, 200),
    latencyMs: Date.now() - started,
    ts: Date.now(),
  }
}

export function querySource(host: string, port: number, timeoutMs = 4000): Promise<QueryResult> {
  return new Promise((resolve) => {
    const started = Date.now()
    const socket = dgram.createSocket('udp4')
    let settled = false
    const finish = (result: QueryResult) => {
      if (settled) return
      settled = true
      try {
        socket.close()
      } catch { /* closed */ }
      resolve(result)
    }
    const timer = setTimeout(() => finish({ online: false, ts: Date.now() }), timeoutMs)

    socket.on('message', (msg) => {
      if (msg.length >= 5 && msg.readInt32LE(0) === -1 && msg[4] === 0x41) {
        // S2C_CHALLENGE: resend with the 4-byte challenge appended
        const challenge = msg.subarray(5, 9)
        socket.send(Buffer.concat([A2S_INFO, challenge]), port, host)
        return
      }
      const info = parseA2sInfo(msg, started)
      if (info) {
        clearTimeout(timer)
        finish(info)
      }
    })
    socket.on('error', () => {
      clearTimeout(timer)
      finish({ online: false, ts: Date.now() })
    })
    socket.send(A2S_INFO, port, host, (err) => {
      if (err) {
        clearTimeout(timer)
        finish({ online: false, ts: Date.now() })
      }
    })
  })
}

const A2S_PLAYER_HEADER = Buffer.from([0xff, 0xff, 0xff, 0xff, 0x55])
/** Challenge -1 asks the server to hand out a real challenge via S2C_CHALLENGE. */
const CHALLENGE_PLACEHOLDER = Buffer.from([0xff, 0xff, 0xff, 0xff])

const MAX_PLAYERS = 100
const MAX_NAME_LEN = 64

/** Drop C0 control characters and DEL (names come from untrusted packets). */
function stripControlChars(raw: string): string {
  let out = ''
  for (const ch of raw) {
    const code = ch.codePointAt(0) ?? 0
    if (code >= 0x20 && code !== 0x7f) out += ch
  }
  return out
}

/**
 * Parse an A2S_PLAYER response (0x44 'D'): byte count, then per player a byte
 * index, null-terminated name, int32 LE score and float32 LE duration seconds.
 * Returns null for anything malformed or truncated — never throws.
 */
export function parseA2sPlayers(msg: Buffer): { name: string; score: number; durationS: number }[] | null {
  if (msg.length < 6 || msg.readInt32LE(0) !== -1) return null
  if (msg[4] !== 0x44) return null // 'D'
  const count = msg[5]
  const players: { name: string; score: number; durationS: number }[] = []
  let p = 6
  for (let i = 0; i < count && players.length < MAX_PLAYERS; i++) {
    if (p >= msg.length) return null
    p += 1 // player index (unreliable; often always 0)
    const end = msg.indexOf(0, p)
    if (end < 0 || end + 9 > msg.length) return null
    const name = stripControlChars(msg.subarray(p, end).toString('utf8')).slice(0, MAX_NAME_LEN)
    const score = msg.readInt32LE(end + 1)
    const durationS = msg.readFloatLE(end + 5)
    p = end + 9
    players.push({ name, score, durationS })
  }
  return players
}

/**
 * A2S_PLAYER query. Resolves the player list, or null on failure/timeout —
 * callers must treat null as "unknown", not as "0 players".
 */
export function querySourcePlayers(host: string, port: number, timeoutMs = 4000): Promise<{ name: string; score: number; durationS: number }[] | null> {
  return new Promise((resolve) => {
    const socket = dgram.createSocket('udp4')
    let settled = false
    const finish = (result: { name: string; score: number; durationS: number }[] | null) => {
      if (settled) return
      settled = true
      try {
        socket.close()
      } catch { /* closed */ }
      resolve(result)
    }
    const timer = setTimeout(() => finish(null), timeoutMs)

    socket.on('message', (msg) => {
      if (msg.length >= 5 && msg.readInt32LE(0) === -1 && msg[4] === 0x41) {
        // S2C_CHALLENGE: resend with the 4-byte challenge appended
        const challenge = msg.subarray(5, 9)
        socket.send(Buffer.concat([A2S_PLAYER_HEADER, challenge]), port, host)
        return
      }
      const players = parseA2sPlayers(msg)
      if (players) {
        clearTimeout(timer)
        finish(players)
      }
    })
    socket.on('error', () => {
      clearTimeout(timer)
      finish(null)
    })
    socket.send(Buffer.concat([A2S_PLAYER_HEADER, CHALLENGE_PLACEHOLDER]), port, host, (err) => {
      if (err) {
        clearTimeout(timer)
        finish(null)
      }
    })
  })
}
