import { test } from 'node:test'
import assert from 'node:assert/strict'
import dgram from 'node:dgram'
import { parseA2sPlayers, querySourcePlayers } from '../../src/query/source.ts'
import { parseMcStatus } from '../../src/query/minecraft.ts'

// ---------------------------------------------------------------------------
// A2S_PLAYER buffer builders
// ---------------------------------------------------------------------------
function playerEntry(index: number, name: string, score: number, durationS: number): Buffer {
  const nameBuf = Buffer.from(name, 'utf8')
  const buf = Buffer.alloc(1 + nameBuf.length + 1 + 8)
  let p = 0
  buf[p++] = index
  nameBuf.copy(buf, p)
  p += nameBuf.length
  buf[p++] = 0
  buf.writeInt32LE(score, p)
  p += 4
  buf.writeFloatLE(durationS, p)
  return buf
}

function playersResponse(entries: Buffer[], count = entries.length): Buffer {
  return Buffer.concat([Buffer.from([0xff, 0xff, 0xff, 0xff, 0x44, count]), ...entries])
}

// ---------------------------------------------------------------------------
// parseA2sPlayers
// ---------------------------------------------------------------------------
test('parseA2sPlayers parses a realistic response', () => {
  // durations chosen to be exactly representable as float32
  const msg = playersResponse([
    playerEntry(0, 'Alice', 12, 123.5),
    playerEntry(1, 'Zoë', -3, 0.25),
    playerEntry(2, 'Bob', 0, 4096.75),
  ])
  assert.deepEqual(parseA2sPlayers(msg), [
    { name: 'Alice', score: 12, durationS: 123.5 },
    { name: 'Zoë', score: -3, durationS: 0.25 },
    { name: 'Bob', score: 0, durationS: 4096.75 },
  ])
})

test('parseA2sPlayers parses an empty player list', () => {
  assert.deepEqual(parseA2sPlayers(playersResponse([])), [])
})

test('parseA2sPlayers returns null on malformed buffers (never throws)', () => {
  assert.equal(parseA2sPlayers(Buffer.alloc(0)), null)
  assert.equal(parseA2sPlayers(Buffer.from([0xff, 0xff, 0xff, 0xff])), null)
  // wrong header int32 (not -1)
  assert.equal(parseA2sPlayers(Buffer.from([0x00, 0x00, 0x00, 0x00, 0x44, 0x00])), null)
  // wrong type byte ('I' info response instead of 'D')
  assert.equal(parseA2sPlayers(Buffer.from([0xff, 0xff, 0xff, 0xff, 0x49, 0x00])), null)
  // S2C_CHALLENGE packet is not a player response
  assert.equal(parseA2sPlayers(Buffer.from([0xff, 0xff, 0xff, 0xff, 0x41, 1, 2, 3, 4])), null)
})

test('parseA2sPlayers returns null on truncated buffers', () => {
  // count says 2 but only one entry present
  assert.equal(parseA2sPlayers(playersResponse([playerEntry(0, 'Solo', 1, 60)], 2)), null)
  // name missing its null terminator
  const noNull = Buffer.concat([Buffer.from([0xff, 0xff, 0xff, 0xff, 0x44, 1, 0]), Buffer.from('NeverEnds', 'utf8')])
  assert.equal(parseA2sPlayers(noNull), null)
  // score/duration cut off after the name
  const full = playersResponse([playerEntry(0, 'Cut', 5, 60)])
  assert.equal(parseA2sPlayers(full.subarray(0, full.length - 3)), null)
})

test('parseA2sPlayers caps names at 64 chars and strips control characters', () => {
  const long = parseA2sPlayers(playersResponse([playerEntry(0, 'x'.repeat(80), 1, 60)]))
  assert.equal(long?.[0]?.name, 'x'.repeat(64))
  const dirty = parseA2sPlayers(playersResponse([playerEntry(0, '\u0001bad\tname\u007f!', 1, 60)]))
  assert.equal(dirty?.[0]?.name, 'badname!')
})

test('parseA2sPlayers caps the list at 100 entries', () => {
  const entries = Array.from({ length: 120 }, (_, i) => playerEntry(i & 0xff, `p${i}`, i, 60))
  const parsed = parseA2sPlayers(playersResponse(entries))
  assert.equal(parsed?.length, 100)
  assert.equal(parsed?.[99]?.name, 'p99')
})

// ---------------------------------------------------------------------------
// querySourcePlayers — live UDP round-trip against a fake Source server
// ---------------------------------------------------------------------------
function bindUdp(server: dgram.Socket): Promise<number> {
  return new Promise((resolve) => {
    server.bind(0, '127.0.0.1', () => resolve((server.address() as { port: number }).port))
  })
}

test('querySourcePlayers completes the challenge handshake against a fake server', async () => {
  const server = dgram.createSocket('udp4')
  const CHALLENGE = Buffer.from([0x11, 0x22, 0x33, 0x44])
  server.on('message', (msg, rinfo) => {
    // expect: ff ff ff ff 55 + 4-byte challenge
    if (msg.length < 9 || msg.readInt32LE(0) !== -1 || msg[4] !== 0x55) return
    const challenge = msg.subarray(5, 9)
    if (challenge.readInt32LE(0) === -1) {
      // placeholder challenge → S2C_CHALLENGE
      server.send(Buffer.concat([Buffer.from([0xff, 0xff, 0xff, 0xff, 0x41]), CHALLENGE]), rinfo.port, rinfo.address)
      return
    }
    if (challenge.equals(CHALLENGE)) {
      server.send(playersResponse([playerEntry(0, 'Alice', 7, 123.5), playerEntry(1, 'Bob', -1, 0.25)]), rinfo.port, rinfo.address)
    }
  })
  const port = await bindUdp(server)
  try {
    const players = await querySourcePlayers('127.0.0.1', port, 2000)
    assert.deepEqual(players, [
      { name: 'Alice', score: 7, durationS: 123.5 },
      { name: 'Bob', score: -1, durationS: 0.25 },
    ])
  } finally {
    server.close()
  }
})

test('querySourcePlayers accepts a direct response when the server skips the challenge', async () => {
  const server = dgram.createSocket('udp4')
  server.on('message', (msg, rinfo) => {
    if (msg.length < 5 || msg.readInt32LE(0) !== -1 || msg[4] !== 0x55) return
    server.send(playersResponse([playerEntry(0, 'Solo', 3, 60)]), rinfo.port, rinfo.address)
  })
  const port = await bindUdp(server)
  try {
    const players = await querySourcePlayers('127.0.0.1', port, 2000)
    assert.deepEqual(players, [{ name: 'Solo', score: 3, durationS: 60 }])
  } finally {
    server.close()
  }
})

test('querySourcePlayers resolves null on timeout', async () => {
  const server = dgram.createSocket('udp4') // bound but never answers
  const port = await bindUdp(server)
  try {
    const players = await querySourcePlayers('127.0.0.1', port, 250)
    assert.equal(players, null)
  } finally {
    server.close()
  }
})

// ---------------------------------------------------------------------------
// parseMcStatus (Minecraft status JSON → QueryResult)
// ---------------------------------------------------------------------------
test('parseMcStatus maps players.sample onto QueryResult.players', () => {
  const result = parseMcStatus(
    {
      version: { name: '1.21' },
      players: { online: 3, max: 20, sample: [{ name: 'Steve', id: 'a' }, { name: 'Alex', id: 'b' }] },
      description: 'A server',
    },
    Date.now(),
  )
  assert.equal(result.online, true)
  assert.equal(result.playersOnline, 3)
  assert.equal(result.playersMax, 20)
  assert.deepEqual(result.players, [{ name: 'Steve' }, { name: 'Alex' }])
})

test('parseMcStatus omits players when there is no sample', () => {
  const noSample = parseMcStatus({ players: { online: 5, max: 20 } }, Date.now())
  assert.ok(!('players' in noSample) || noSample.players === undefined)
  const badSample = parseMcStatus({ players: { online: 5, max: 20, sample: 'nope' } }, Date.now())
  assert.equal(badSample.players, undefined)
})

test('parseMcStatus skips sample entries without a string name', () => {
  const result = parseMcStatus(
    { players: { online: 2, max: 10, sample: [null, 42, { id: 'x' }, { name: 7 }, { name: 'Real' }] } },
    Date.now(),
  )
  assert.deepEqual(result.players, [{ name: 'Real' }])
})

test('parseMcStatus strips § color codes and control chars, caps at 64 chars', () => {
  const result = parseMcStatus(
    {
      players: {
        online: 3,
        max: 10,
        sample: [{ name: '§aSteve§r' }, { name: '\u0001we\tird\u007f' }, { name: 'y'.repeat(90) }],
      },
    },
    Date.now(),
  )
  assert.deepEqual(result.players, [{ name: 'Steve' }, { name: 'weird' }, { name: 'y'.repeat(64) }])
})

test('parseMcStatus caps the sample at 100 entries', () => {
  const sample = Array.from({ length: 130 }, (_, i) => ({ name: `p${i}` }))
  const result = parseMcStatus({ players: { online: 130, max: 200, sample } }, Date.now())
  assert.equal(result.players?.length, 100)
  assert.deepEqual(result.players?.[99], { name: 'p99' })
})
