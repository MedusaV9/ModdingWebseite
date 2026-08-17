import { test } from 'node:test'
import assert from 'node:assert/strict'
import net from 'node:net'
import { RconClient, rconExec } from '../../src/lib/rcon.ts'

const AUTH = 3
const AUTH_RESPONSE = 2
const EXECCOMMAND = 2
const RESPONSE_VALUE = 0

function encode(id: number, type: number, body: string): Buffer {
  const bodyBuf = Buffer.from(body, 'utf8')
  const buf = Buffer.alloc(4 + 4 + 4 + bodyBuf.length + 2)
  buf.writeInt32LE(bodyBuf.length + 10, 0)
  buf.writeInt32LE(id, 4)
  buf.writeInt32LE(type, 8)
  bodyBuf.copy(buf, 12)
  return buf
}

interface MockPacket {
  id: number
  type: number
  body: string
}

type Reply = (id: number, type: number, body: string) => void
type Handler = (pkt: MockPacket, reply: Reply, socket: net.Socket) => void

interface Mock {
  port: number
  close: () => Promise<void>
}

/** Minimal RCON server: parses framed packets from the stream, calls handler per packet. */
async function startMock(handler: Handler): Promise<Mock> {
  const sockets = new Set<net.Socket>()
  const server = net.createServer((socket) => {
    sockets.add(socket)
    socket.on('close', () => sockets.delete(socket))
    socket.on('error', () => {})
    let buf = Buffer.alloc(0)
    socket.on('data', (chunk) => {
      buf = Buffer.concat([buf, chunk])
      while (buf.length >= 4) {
        const size = buf.readInt32LE(0)
        if (buf.length < 4 + size) break
        const pkt: MockPacket = {
          id: buf.readInt32LE(4),
          type: buf.readInt32LE(8),
          body: buf.subarray(12, 4 + size - 2).toString('utf8'),
        }
        buf = buf.subarray(4 + size)
        handler(pkt, (id, type, body) => socket.write(encode(id, type, body)), socket)
      }
    })
  })
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  const port = (server.address() as net.AddressInfo).port
  return {
    port,
    close: () =>
      new Promise<void>((resolve) => {
        for (const s of sockets) s.destroy()
        server.close(() => resolve())
      }),
  }
}

/** srcds-like behavior: empty RESPONSE_VALUE + AUTH_RESPONSE on auth, fragments on exec, sentinel echo + junk trailer. */
function sourceHandler(password: string, respond: (cmd: string) => string[]): Handler {
  return (pkt, reply) => {
    if (pkt.type === AUTH) {
      reply(pkt.id, RESPONSE_VALUE, '')
      reply(pkt.body === password ? pkt.id : -1, AUTH_RESPONSE, '')
    } else if (pkt.type === EXECCOMMAND) {
      for (const frag of respond(pkt.body)) reply(pkt.id, RESPONSE_VALUE, frag)
    } else if (pkt.type === RESPONSE_VALUE) {
      reply(pkt.id, RESPONSE_VALUE, '')
      reply(pkt.id, RESPONSE_VALUE, '\u0000\u0001') // junk trailer like real srcds
    }
  }
}

test('happy path: auth + single-packet exec', async () => {
  const mock = await startMock(sourceHandler('hunter2', (cmd) => [`echo:${cmd}`]))
  const client = new RconClient({ host: '127.0.0.1', port: mock.port, password: 'hunter2', timeoutMs: 2000 })
  try {
    await client.connect()
    assert.equal(client.connected, true)
    const out = await client.exec('status')
    assert.equal(out, 'echo:status')
  } finally {
    client.close()
    await mock.close()
  }
})

test('auth response without preceding empty RESPONSE_VALUE', async () => {
  const mock = await startMock((pkt, reply) => {
    if (pkt.type === AUTH) {
      // Other order: AUTH_RESPONSE first, stray empty RESPONSE_VALUE after
      reply(pkt.id, AUTH_RESPONSE, '')
      reply(pkt.id, RESPONSE_VALUE, '')
    }
  })
  const client = new RconClient({ host: '127.0.0.1', port: mock.port, password: 'pw', timeoutMs: 2000 })
  try {
    await client.connect()
    assert.equal(client.connected, true)
  } finally {
    client.close()
    await mock.close()
  }
})

test('multi-packet response is reassembled via sentinel echo', async () => {
  const mock = await startMock(sourceHandler('pw', () => ['part-one|', 'part-two']))
  const client = new RconClient({ host: '127.0.0.1', port: mock.port, password: 'pw', timeoutMs: 2000 })
  try {
    await client.connect()
    const out = await client.exec('cvarlist')
    assert.equal(out, 'part-one|part-two')
  } finally {
    client.close()
    await mock.close()
  }
})

test('wrong password rejects with authentication failure', async () => {
  const mock = await startMock(sourceHandler('correct', () => ['']))
  const client = new RconClient({ host: '127.0.0.1', port: mock.port, password: 'wrong', timeoutMs: 2000 })
  try {
    await assert.rejects(client.connect(), /rcon authentication failed/)
    assert.equal(client.connected, false)
  } finally {
    client.close()
    await mock.close()
  }
})

test('packets fragmented at the TCP level are parsed correctly', async () => {
  const mock = await startMock((pkt, reply, socket) => {
    if (pkt.type === AUTH) {
      // Split the auth response mid-packet across two writes
      const full = Buffer.concat([encode(pkt.id, RESPONSE_VALUE, ''), encode(pkt.id, AUTH_RESPONSE, '')])
      socket.write(full.subarray(0, 7))
      setTimeout(() => socket.write(full.subarray(7)), 15)
    } else if (pkt.type === EXECCOMMAND) {
      const full = encode(pkt.id, RESPONSE_VALUE, 'hello fragmented world')
      socket.write(full.subarray(0, 10))
      setTimeout(() => socket.write(full.subarray(10)), 15)
    } else if (pkt.type === RESPONSE_VALUE) {
      // Echo the sentinel only after the delayed fragment above was flushed
      setTimeout(() => reply(pkt.id, RESPONSE_VALUE, ''), 40)
    }
  })
  const client = new RconClient({ host: '127.0.0.1', port: mock.port, password: 'pw', timeoutMs: 2000 })
  try {
    await client.connect()
    const out = await client.exec('say hi')
    assert.equal(out, 'hello fragmented world')
  } finally {
    client.close()
    await mock.close()
  }
})

test('quiet-period fallback resolves when the server never echoes the sentinel', async () => {
  const mock = await startMock((pkt, reply) => {
    if (pkt.type === AUTH) reply(pkt.id, AUTH_RESPONSE, '')
    else if (pkt.type === EXECCOMMAND) reply(pkt.id, RESPONSE_VALUE, 'no sentinel here')
    // sentinel RESPONSE_VALUE is silently ignored
  })
  const client = new RconClient({ host: '127.0.0.1', port: mock.port, password: 'pw', timeoutMs: 3000 })
  try {
    await client.connect()
    const started = Date.now()
    const out = await client.exec('status')
    assert.equal(out, 'no sentinel here')
    assert.ok(Date.now() - started >= 250, 'should have waited for the quiet period')
  } finally {
    client.close()
    await mock.close()
  }
})

test('connect times out when the server never responds', async () => {
  const mock = await startMock(() => {}) // accepts, ignores all packets
  const client = new RconClient({ host: '127.0.0.1', port: mock.port, password: 'pw', timeoutMs: 500 })
  try {
    const started = Date.now()
    await assert.rejects(client.connect(), /rcon timeout/)
    assert.ok(Date.now() - started < 2000, 'should reject near the configured timeout')
    assert.equal(client.connected, false)
  } finally {
    client.close()
    await mock.close()
  }
})

test('exec times out when the server stops responding after auth', async () => {
  const mock = await startMock((pkt, reply) => {
    if (pkt.type === AUTH) reply(pkt.id, AUTH_RESPONSE, '')
  })
  const client = new RconClient({ host: '127.0.0.1', port: mock.port, password: 'pw', timeoutMs: 500 })
  try {
    await client.connect()
    await assert.rejects(client.exec('status'), /rcon timeout/)
    assert.equal(client.connected, false)
  } finally {
    client.close()
    await mock.close()
  }
})

test('oversized responses are rejected', async () => {
  const chunk = 'x'.repeat(60 * 1024)
  const mock = await startMock((pkt, reply) => {
    if (pkt.type === AUTH) reply(pkt.id, AUTH_RESPONSE, '')
    else if (pkt.type === EXECCOMMAND) {
      for (let i = 0; i < 20; i++) reply(pkt.id, RESPONSE_VALUE, chunk) // ~1.2 MiB total
    }
  })
  const client = new RconClient({ host: '127.0.0.1', port: mock.port, password: 'pw', timeoutMs: 3000 })
  try {
    await client.connect()
    await assert.rejects(client.exec('dump'), /rcon response too large/)
  } finally {
    client.close()
    await mock.close()
  }
})

test('rconExec one-shot helper connects, runs and closes', async () => {
  const mock = await startMock(sourceHandler('pw', (cmd) => [`ran:${cmd}`]))
  try {
    const out = await rconExec({ host: '127.0.0.1', port: mock.port, password: 'pw', timeoutMs: 2000 }, 'version')
    assert.equal(out, 'ran:version')
  } finally {
    await mock.close()
  }
})
