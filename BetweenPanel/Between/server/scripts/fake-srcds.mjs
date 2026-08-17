#!/usr/bin/env node
/**
 * fake-srcds — a tiny stand-in for a Source dedicated server, for developing
 * and demoing Between's RCON console and A2S player queries without a 30 GB
 * game install. Implements:
 *   - Source RCON over TCP (auth, exec, sentinel echo, `quit` shuts down)
 *   - A2S_INFO + A2S_PLAYER over UDP (with S2C_CHALLENGE handshake)
 *
 * Usage:
 *   node fake-srcds.mjs --game-port 27015 --rcon-port 27015 \
 *     --password changeme --players 3 --name "My Fake Server"
 */
import net from 'node:net'
import dgram from 'node:dgram'

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`)
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : def
}

const GAME_PORT = Number(arg('game-port', '27015'))
const RCON_PORT = Number(arg('rcon-port', String(GAME_PORT)))
const PASSWORD = String(arg('password', 'changeme'))
const NAME = String(arg('name', 'fake-srcds'))
const PLAYER_COUNT = Number(arg('players', '3'))
const MAX_PLAYERS = 16

const FAKE_NAMES = ['Gordon', 'Alyx', 'Barney', 'Kleiner', 'Eli', 'Judith', 'GMan', 'Chell']
const startedAt = Date.now()
const players = Array.from({ length: Math.min(PLAYER_COUNT, FAKE_NAMES.length) }, (_, i) => ({
  name: FAKE_NAMES[i],
  score: (i + 1) * 7,
}))

// ---------------------------------------------------------------------------
// RCON (TCP)
// ---------------------------------------------------------------------------
const SERVERDATA_AUTH = 3
const SERVERDATA_AUTH_RESPONSE = 2
const SERVERDATA_EXECCOMMAND = 2
const SERVERDATA_RESPONSE_VALUE = 0

function rconPacket(id, type, body) {
  const bodyBuf = Buffer.from(body, 'utf8')
  const packet = Buffer.alloc(4 + 4 + 4 + bodyBuf.length + 2)
  packet.writeInt32LE(4 + 4 + bodyBuf.length + 2, 0)
  packet.writeInt32LE(id, 4)
  packet.writeInt32LE(type, 8)
  bodyBuf.copy(packet, 12)
  return packet
}

function handleCommand(cmd) {
  const [word, ...rest] = cmd.trim().split(/\s+/)
  switch (word) {
    case 'status': {
      const uptimeS = Math.floor((Date.now() - startedAt) / 1000)
      return [
        `hostname: ${NAME}`,
        `version : 1.0.0.0 fake-srcds`,
        `udp/ip  : 127.0.0.1:${GAME_PORT}`,
        `players : ${players.length} humans, 0 bots (${MAX_PLAYERS} max)`,
        `uptime  : ${uptimeS}s`,
        ...players.map((p, i) => `# ${i + 1} "${p.name}" score ${p.score}`),
      ].join('\n')
    }
    case 'echo':
      return rest.join(' ')
    case 'say':
      console.log(`[chat] Console: ${rest.join(' ')}`)
      return ''
    case 'kick': {
      // kick Name / kick "Name With Spaces" — strip optional quotes like real srcds.
      const target = rest.join(' ').replace(/^"(.*)"$/, '$1')
      const idx = players.findIndex((p) => p.name.toLowerCase() === target.toLowerCase())
      if (idx === -1) return `Can't kick "${target}" — player not found.`
      players.splice(idx, 1)
      console.log(`[fake-srcds] Kicked "${target}" (${players.length}/${MAX_PLAYERS} remain).`)
      return `Kicked "${target}"`
    }
    case 'quit':
      setTimeout(() => {
        console.log('[fake-srcds] quit received via RCON — shutting down.')
        process.exit(0)
      }, 100)
      return 'Shutting down...'
    default:
      return `Unknown command "${word}"`
  }
}

const rconServer = net.createServer((socket) => {
  let buf = Buffer.alloc(0)
  let authed = false
  socket.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk])
    while (buf.length >= 4) {
      const size = buf.readInt32LE(0)
      if (buf.length < 4 + size) break
      const id = buf.readInt32LE(4)
      const type = buf.readInt32LE(8)
      const body = buf.subarray(12, 4 + size - 2).toString('utf8')
      buf = buf.subarray(4 + size)

      if (type === SERVERDATA_AUTH) {
        if (body === PASSWORD) {
          authed = true
          // Real srcds sends an empty RESPONSE_VALUE before the auth response.
          socket.write(rconPacket(id, SERVERDATA_RESPONSE_VALUE, ''))
          socket.write(rconPacket(id, SERVERDATA_AUTH_RESPONSE, ''))
          console.log('[fake-srcds] RCON client authenticated.')
        } else {
          socket.write(rconPacket(-1, SERVERDATA_AUTH_RESPONSE, ''))
          console.log('[fake-srcds] RCON auth REJECTED (wrong password).')
        }
      } else if (type === SERVERDATA_EXECCOMMAND && authed) {
        console.log(`[fake-srcds] RCON exec: ${body}`)
        socket.write(rconPacket(id, SERVERDATA_RESPONSE_VALUE, handleCommand(body)))
      } else if (type === SERVERDATA_RESPONSE_VALUE && authed) {
        // Sentinel: echo an empty response so clients know the reply is done.
        socket.write(rconPacket(id, SERVERDATA_RESPONSE_VALUE, ''))
      }
    }
  })
  socket.on('error', () => socket.destroy())
})
rconServer.listen(RCON_PORT, () => console.log(`[fake-srcds] RCON listening on tcp/${RCON_PORT}`))

// ---------------------------------------------------------------------------
// A2S (UDP)
// ---------------------------------------------------------------------------
const CHALLENGE = Buffer.from([0x11, 0x22, 0x33, 0x44])

function a2sInfoResponse() {
  const parts = [
    Buffer.from([0xff, 0xff, 0xff, 0xff, 0x49, 0x11]),
    Buffer.from(`${NAME}\0`, 'utf8'),
    Buffer.from('de_dust2\0', 'utf8'),
    Buffer.from('fake\0', 'utf8'),
    Buffer.from('Fake Source Game\0', 'utf8'),
  ]
  const tail = Buffer.alloc(9)
  tail.writeInt16LE(999, 0) // appid
  tail[2] = players.length
  tail[3] = MAX_PLAYERS
  tail[4] = 0 // bots
  tail[5] = 0x64 // 'd' dedicated
  tail[6] = 0x6c // 'l' linux
  tail[7] = 0 // public
  tail[8] = 0 // no VAC
  return Buffer.concat([...parts, tail, Buffer.from('1.0.0.0\0', 'utf8'), Buffer.from([0x00])])
}

function a2sPlayersResponse() {
  const chunks = [Buffer.from([0xff, 0xff, 0xff, 0xff, 0x44, players.length])]
  players.forEach((p, i) => {
    const head = Buffer.from([i])
    const name = Buffer.from(`${p.name}\0`, 'utf8')
    const tail = Buffer.alloc(8)
    tail.writeInt32LE(p.score, 0)
    tail.writeFloatLE((Date.now() - startedAt) / 1000, 4)
    chunks.push(head, name, tail)
  })
  return Buffer.concat(chunks)
}

const udp = dgram.createSocket('udp4')
udp.on('message', (msg, rinfo) => {
  if (msg.length < 5 || msg.readInt32LE(0) !== -1) return
  const type = msg[4]
  const hasChallenge = msg.length >= 9 && msg.subarray(msg.length - 4).equals(CHALLENGE)
  if (type === 0x54) {
    // A2S_INFO — demand a challenge first, like modern srcds builds.
    if (hasChallenge) udp.send(a2sInfoResponse(), rinfo.port, rinfo.address)
    else udp.send(Buffer.concat([Buffer.from([0xff, 0xff, 0xff, 0xff, 0x41]), CHALLENGE]), rinfo.port, rinfo.address)
  } else if (type === 0x55) {
    if (hasChallenge) udp.send(a2sPlayersResponse(), rinfo.port, rinfo.address)
    else udp.send(Buffer.concat([Buffer.from([0xff, 0xff, 0xff, 0xff, 0x41]), CHALLENGE]), rinfo.port, rinfo.address)
  }
})
udp.bind(GAME_PORT, () => console.log(`[fake-srcds] A2S listening on udp/${GAME_PORT}`))

process.on('SIGTERM', () => {
  console.log('[fake-srcds] SIGTERM — bye.')
  process.exit(0)
})
process.on('SIGINT', () => {
  console.log('[fake-srcds] SIGINT — bye.')
  process.exit(0)
})

console.log(`[fake-srcds] "${NAME}" starting with ${players.length}/${MAX_PLAYERS} fake players...`)
setTimeout(() => console.log('[fake-srcds] Server is listening and ready.'), 300)
