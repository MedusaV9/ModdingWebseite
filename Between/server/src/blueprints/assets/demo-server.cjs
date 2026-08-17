#!/usr/bin/env node
/**
 * Between demo game server — a tiny fake game server used to test and demo
 * the panel end-to-end without downloading a real game. Speaks a Minecraft-ish
 * console dialect: help, say, list/players, tps, seed, crash, stop.
 * Opens a real TCP port so port allocation and conflict checks are honest.
 */
const net = require('net')

const PORT = parseInt(process.env.DEMO_PORT || process.argv[2] || '27777', 10)
const NAME = process.env.DEMO_NAME || 'Between Demo Server'
const FAKE_PLAYERS = ['Steve', 'Alex', 'Herobrine', 'Notch', 'Kelpie', 'Raven', 'Mango', 'Pixel']
let online = []
let startedAt = Date.now()
let stopping = false

function ts() {
  const d = new Date()
  const p = (n) => String(n).padStart(2, '0')
  return `[${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}]`
}
function log(level, msg) {
  console.log(`${ts()} [Server thread/${level}]: ${msg}`)
}

log('INFO', `Starting ${NAME} version 1.0.0`)
log('INFO', `Loading properties`)
setTimeout(() => log('INFO', 'Preparing level "world"'), 250)
setTimeout(() => log('INFO', 'Preparing spawn area: 44%'), 600)
setTimeout(() => log('INFO', 'Preparing spawn area: 92%'), 900)

const server = net.createServer((socket) => {
  socket.write(`${NAME} | players: ${online.length} | uptime: ${Math.round((Date.now() - startedAt) / 1000)}s\n`)
  socket.end()
})
server.on('error', (err) => {
  log('ERROR', `Failed to bind port ${PORT}: ${err.code || err.message}`)
  process.exit(1)
})

setTimeout(() => {
  server.listen(PORT, () => {
    const took = ((Date.now() - startedAt) / 1000).toFixed(3)
    log('INFO', `Listening on 0.0.0.0:${PORT}`)
    log('INFO', `Done (${took}s)! For help, type "help"`)
  })
}, 1200)

// Fake player churn + autosave chatter
const churn = setInterval(() => {
  if (stopping) return
  if (Math.random() < 0.5 && online.length < 6) {
    const candidates = FAKE_PLAYERS.filter((p) => !online.includes(p))
    if (candidates.length) {
      const who = candidates[Math.floor(Math.random() * candidates.length)]
      online.push(who)
      log('INFO', `${who} joined the game`)
    }
  } else if (online.length > 0) {
    const who = online.splice(Math.floor(Math.random() * online.length), 1)[0]
    log('INFO', `${who} left the game`)
  }
}, 25000)
const autosave = setInterval(() => {
  if (!stopping) log('INFO', 'Automatic saving is complete')
}, 60000)

function shutdown(code) {
  if (stopping) return
  stopping = true
  log('INFO', 'Stopping the server')
  log('INFO', 'Saving chunks for level "world"')
  clearInterval(churn)
  clearInterval(autosave)
  server.close()
  setTimeout(() => {
    log('INFO', 'ThreadedAnvilChunkStorage: All dimensions are saved')
    process.exit(code)
  }, 700)
}

process.on('SIGTERM', () => shutdown(0))
process.on('SIGINT', () => shutdown(0))

let buf = ''
process.stdin.on('data', (chunk) => {
  buf += chunk.toString()
  const lines = buf.split(/\r?\n/)
  buf = lines.pop() || ''
  for (const raw of lines) {
    const line = raw.trim()
    if (!line) continue
    const [cmd, ...rest] = line.split(/\s+/)
    switch (cmd.toLowerCase()) {
      case 'help':
        log('INFO', 'Available commands: help, say <msg>, list, players, tps, seed, crash, stop')
        break
      case 'say':
        log('INFO', `[Server] ${rest.join(' ')}`)
        break
      case 'list':
      case 'players':
        log('INFO', `There are ${online.length} of a max of 20 players online: ${online.join(', ')}`)
        break
      case 'tps':
        log('INFO', `TPS from last 1m, 5m, 15m: 20.0, 20.0, 19.98`)
        break
      case 'seed':
        log('INFO', 'Seed: [-4200424242424242]')
        break
      case 'crash':
        log('ERROR', 'Simulated crash requested from console!')
        log('ERROR', 'java.lang.IllegalStateException: entity Herobrine is not (never was?) real')
        process.exit(1)
        break
      case 'stop':
        shutdown(0)
        break
      default:
        log('INFO', `Unknown command "${cmd}". Type "help" for help.`)
    }
  }
})
