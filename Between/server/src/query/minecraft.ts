/**
 * Minecraft Java "Server List Ping" (TCP) — hand-rolled varint protocol.
 * https://wiki.vg/Server_List_Ping
 */
import net from 'node:net'
import type { QueryResult } from '../types.ts'

export function writeVarInt(value: number): Buffer {
  const bytes: number[] = []
  let v = value >>> 0
  do {
    let temp = v & 0x7f
    v >>>= 7
    if (v !== 0) temp |= 0x80
    bytes.push(temp)
  } while (v !== 0)
  return Buffer.from(bytes)
}

export function readVarInt(buf: Buffer, offset: number): { value: number; size: number } {
  let numRead = 0
  let result = 0
  let read: number
  do {
    if (offset + numRead >= buf.length) throw new Error('varint out of bounds')
    read = buf[offset + numRead]
    result |= (read & 0x7f) << (7 * numRead)
    numRead++
    if (numRead > 5) throw new Error('varint too big')
  } while ((read & 0x80) !== 0)
  return { value: result, size: numRead }
}

function packet(id: number, payload: Buffer): Buffer {
  const body = Buffer.concat([writeVarInt(id), payload])
  return Buffer.concat([writeVarInt(body.length), body])
}

function mcString(s: string): Buffer {
  const data = Buffer.from(s, 'utf8')
  return Buffer.concat([writeVarInt(data.length), data])
}

export interface McStatus {
  version?: { name?: string }
  players?: { online?: number; max?: number; sample?: unknown }
  description?: unknown
}

function extractMotd(desc: unknown): string {
  if (typeof desc === 'string') return desc
  if (desc && typeof desc === 'object') {
    const d = desc as { text?: string; extra?: unknown[] }
    let out = d.text ?? ''
    if (Array.isArray(d.extra)) out += d.extra.map((e) => extractMotd(e)).join('')
    return out
  }
  return ''
}

const MAX_PLAYERS = 100
const MAX_NAME_LEN = 64

/** Strip Minecraft § formatting codes plus control characters, and cap the length. */
function sanitizePlayerName(raw: string): string {
  const noCodes = raw.replace(/\u00a7./g, '')
  let out = ''
  for (const ch of noCodes) {
    const code = ch.codePointAt(0) ?? 0
    if (code >= 0x20 && code !== 0x7f) out += ch
  }
  return out.slice(0, MAX_NAME_LEN)
}

/** Map a parsed status-response JSON document onto a QueryResult (pure, unit-testable). */
export function parseMcStatus(status: McStatus, started: number): QueryResult {
  const result: QueryResult = {
    online: true,
    playersOnline: status.players?.online ?? 0,
    playersMax: status.players?.max ?? 0,
    version: status.version?.name,
    motd: extractMotd(status.description).slice(0, 200),
    latencyMs: Date.now() - started,
    ts: Date.now(),
  }
  const sample = status.players?.sample
  if (Array.isArray(sample)) {
    const players: { name: string }[] = []
    for (const entry of sample) {
      if (players.length >= MAX_PLAYERS) break
      const name = (entry as { name?: unknown } | null)?.name
      if (typeof name === 'string') players.push({ name: sanitizePlayerName(name) })
    }
    result.players = players
  }
  return result
}

export function queryMinecraft(host: string, port: number, timeoutMs = 4000): Promise<QueryResult> {
  return new Promise((resolve) => {
    const started = Date.now()
    const socket = net.connect({ host, port })
    let buffer = Buffer.alloc(0)
    let settled = false
    let timer: ReturnType<typeof setTimeout>

    const fail = () => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      socket.destroy()
      resolve({ online: false, ts: Date.now() })
    }
    timer = setTimeout(fail, timeoutMs)

    socket.on('connect', () => {
      // handshake: protocol -1, next state 1 (status), then status request
      const handshake = packet(
        0x00,
        Buffer.concat([writeVarInt(0xffffff), mcString(host), Buffer.from([(port >> 8) & 0xff, port & 0xff]), writeVarInt(1)]),
      )
      socket.write(Buffer.concat([handshake, packet(0x00, Buffer.alloc(0))]))
    })
    socket.on('data', (chunk) => {
      buffer = Buffer.concat([buffer, chunk])
      try {
        const len = readVarInt(buffer, 0)
        if (buffer.length < len.size + len.value) return // wait for more
        const pid = readVarInt(buffer, len.size)
        if (pid.value !== 0x00) return fail()
        const strLen = readVarInt(buffer, len.size + pid.size)
        const start = len.size + pid.size + strLen.size
        const json = buffer.subarray(start, start + strLen.value).toString('utf8')
        const status = JSON.parse(json) as McStatus
        clearTimeout(timer)
        settled = true
        socket.destroy()
        resolve(parseMcStatus(status, started))
      } catch {
        // wait for more data unless clearly broken
        if (buffer.length > 1024 * 1024) fail()
      }
    })
    socket.on('error', fail)
    socket.on('close', () => fail())
  })
}
