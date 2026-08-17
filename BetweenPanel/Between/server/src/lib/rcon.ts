/**
 * Valve Source RCON client (TCP) — hand-rolled on node:net.
 * https://developer.valvesoftware.com/wiki/Source_RCON_Protocol
 *
 * Wire format (all int32 little-endian):
 *   size  — byte count of the rest of the packet (id + type + body + 2 nulls)
 *   id    — client-chosen request id, echoed back by the server
 *   type  — 3=AUTH, 2=AUTH_RESPONSE (server) / EXECCOMMAND (client), 0=RESPONSE_VALUE
 *   body  — null-terminated UTF-8 string, followed by one extra null byte
 *
 * Auth: the server may send an empty RESPONSE_VALUE before (or after) the
 * AUTH_RESPONSE; the AUTH_RESPONSE id equals the request id on success and
 * is -1 on a wrong password.
 *
 * Multi-packet responses: large responses are split across several
 * RESPONSE_VALUE packets with no end marker. After each EXECCOMMAND we send
 * a sentinel RESPONSE_VALUE packet with the next id — compliant servers
 * process packets in order and echo the sentinel id back once every response
 * fragment has been sent. Servers that do not echo are handled with a
 * quiet-period fallback (resolve after a short pause with no new data).
 */
import net from 'node:net'

const SERVERDATA_AUTH = 3
const SERVERDATA_AUTH_RESPONSE = 2
const SERVERDATA_EXECCOMMAND = 2
const SERVERDATA_RESPONSE_VALUE = 0

const DEFAULT_TIMEOUT_MS = 5000
const QUIET_PERIOD_MS = 300
const MAX_RESPONSE_BYTES = 1024 * 1024
/** Sanity cap on a single packet's declared size (spec max is ~4 KiB). */
const MAX_PACKET_BYTES = 64 * 1024

export interface RconOptions {
  host: string
  port: number
  password: string
  timeoutMs?: number
}

interface RconPacket {
  id: number
  type: number
  body: string
}

interface PendingOp {
  kind: 'auth' | 'exec'
  id: number
  /** Exec only: id of the echoed RESPONSE_VALUE marking end-of-response. */
  sentinelId: number
  chunks: string[]
  bytes: number
  resolve: (value: string) => void
  reject: (err: Error) => void
  deadline: NodeJS.Timeout
  quiet: NodeJS.Timeout | null
}

function encodePacket(id: number, type: number, body: string): Buffer {
  const bodyBuf = Buffer.from(body, 'utf8')
  const buf = Buffer.alloc(4 + 4 + 4 + bodyBuf.length + 2)
  buf.writeInt32LE(bodyBuf.length + 10, 0)
  buf.writeInt32LE(id, 4)
  buf.writeInt32LE(type, 8)
  bodyBuf.copy(buf, 12)
  // last two bytes stay 0: body terminator + packet terminator
  return buf
}

export class RconClient {
  private readonly opts: RconOptions
  private socket: net.Socket | null = null
  private recvBuf: Buffer = Buffer.alloc(0)
  private authed = false
  private closed = false
  private nextId = 1
  private pending: PendingOp | null = null
  /** Serializes exec calls so responses can never interleave. */
  private queue: Promise<unknown> = Promise.resolve()

  constructor(opts: RconOptions) {
    this.opts = opts
  }

  get connected(): boolean {
    return this.authed && this.socket !== null && !this.socket.destroyed
  }

  /** TCP connect + authenticate. Rejects on wrong password or timeout. */
  connect(): Promise<void> {
    if (this.socket) return Promise.reject(new Error('rcon client already connected'))
    if (this.closed) return Promise.reject(new Error('rcon client closed'))
    return new Promise<void>((resolve, reject) => {
      // One deadline covers the whole TCP connect + auth round-trip
      const op = this.makePending('auth', this.takeId(), () => resolve(), reject)
      this.pending = op
      const socket = net.connect({ host: this.opts.host, port: this.opts.port })
      this.socket = socket
      socket.setNoDelay(true)
      socket.on('data', (chunk) => this.onData(chunk))
      socket.on('error', (err) => this.fail(new Error(`rcon socket error: ${err.message}`)))
      socket.on('close', () => this.fail(new Error('rcon connection closed')))
      socket.once('connect', () => {
        socket.write(encodePacket(op.id, SERVERDATA_AUTH, this.opts.password))
      })
    })
  }

  /** Send a command and resolve with the full (possibly multi-packet) response. */
  exec(command: string): Promise<string> {
    const run = this.queue.then(() => this.execNow(command))
    this.queue = run.catch(() => {})
    return run
  }

  close(): void {
    this.closed = true
    this.fail(new Error('rcon client closed'))
  }

  private execNow(command: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      if (!this.connected || !this.socket) {
        reject(new Error('rcon client not connected'))
        return
      }
      const op = this.makePending('exec', this.takeId(), resolve, reject)
      op.sentinelId = this.takeId()
      this.pending = op
      this.socket.write(encodePacket(op.id, SERVERDATA_EXECCOMMAND, command))
      // Sentinel: servers echo this back after all fragments of the response
      this.socket.write(encodePacket(op.sentinelId, SERVERDATA_RESPONSE_VALUE, ''))
    })
  }

  private makePending(kind: 'auth' | 'exec', id: number, resolve: (v: string) => void, reject: (e: Error) => void): PendingOp {
    const timeoutMs = this.opts.timeoutMs ?? DEFAULT_TIMEOUT_MS
    const deadline = setTimeout(() => this.fail(new Error('rcon timeout')), timeoutMs)
    deadline.unref()
    return { kind, id, sentinelId: -1, chunks: [], bytes: 0, resolve, reject, deadline, quiet: null }
  }

  private takeId(): number {
    const id = this.nextId
    this.nextId = this.nextId >= 0x7ffffffe ? 1 : this.nextId + 1
    return id
  }

  private onData(chunk: Buffer): void {
    this.recvBuf = this.recvBuf.length === 0 ? chunk : Buffer.concat([this.recvBuf, chunk])
    while (this.recvBuf.length >= 4) {
      const size = this.recvBuf.readInt32LE(0)
      if (size < 10 || size > MAX_PACKET_BYTES) {
        this.fail(new Error(`rcon protocol error: bad packet size ${size}`))
        return
      }
      if (this.recvBuf.length < 4 + size) break // partial packet, wait for more data
      const packet: RconPacket = {
        id: this.recvBuf.readInt32LE(4),
        type: this.recvBuf.readInt32LE(8),
        body: this.recvBuf.subarray(12, 4 + size - 2).toString('utf8'),
      }
      this.recvBuf = this.recvBuf.subarray(4 + size)
      this.dispatch(packet)
      if (!this.socket) return // dispatch may have torn the connection down
    }
  }

  private dispatch(packet: RconPacket): void {
    const op = this.pending
    if (!op) return // stray packet (e.g. junk echoed after a sentinel); ignore

    if (op.kind === 'auth') {
      // An empty RESPONSE_VALUE may arrive before or after the AUTH_RESPONSE
      if (packet.type !== SERVERDATA_AUTH_RESPONSE) return
      if (packet.id === -1 || packet.id !== op.id) {
        this.fail(new Error('rcon authentication failed'))
        return
      }
      this.authed = true
      this.settle(op, '')
      return
    }

    if (packet.type !== SERVERDATA_RESPONSE_VALUE) return
    if (packet.id === op.sentinelId) {
      this.settle(op, op.chunks.join(''))
      return
    }
    if (packet.id !== op.id) return
    op.bytes += Buffer.byteLength(packet.body, 'utf8')
    if (op.bytes > MAX_RESPONSE_BYTES) {
      this.fail(new Error('rcon response too large'))
      return
    }
    op.chunks.push(packet.body)
    // Fallback for servers that never echo the sentinel: resolve after a
    // quiet period once at least one fragment has arrived.
    if (op.quiet) clearTimeout(op.quiet)
    op.quiet = setTimeout(() => this.settle(op, op.chunks.join('')), QUIET_PERIOD_MS)
    op.quiet.unref()
  }

  private settle(op: PendingOp, result: string): void {
    clearTimeout(op.deadline)
    if (op.quiet) clearTimeout(op.quiet)
    if (this.pending === op) this.pending = null
    op.resolve(result)
  }

  /** Reject any pending operation and tear the connection down. */
  private fail(err: Error): void {
    const op = this.pending
    this.pending = null
    this.authed = false
    this.recvBuf = Buffer.alloc(0)
    const socket = this.socket
    this.socket = null
    if (socket && !socket.destroyed) socket.destroy()
    if (op) {
      clearTimeout(op.deadline)
      if (op.quiet) clearTimeout(op.quiet)
      op.reject(err)
    }
  }
}

/** One-shot helper: connect, run a single command, always close. */
export async function rconExec(opts: RconOptions, command: string): Promise<string> {
  const client = new RconClient(opts)
  try {
    await client.connect()
    return await client.exec(command)
  } finally {
    client.close()
  }
}
