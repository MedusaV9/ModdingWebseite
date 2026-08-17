#!/usr/bin/env node
/**
 * Between dev runner — starts the API server (tsx watch) and the Vite web dev
 * server together, with prefixed output. Cross-platform (Linux/Windows/macOS).
 */
import { spawn } from 'node:child_process'

const procs = []
let shuttingDown = false

const COLORS = { server: '\x1b[36m', web: '\x1b[35m', reset: '\x1b[0m' }

function run(name, command) {
  const child = spawn(command, { shell: true, stdio: ['ignore', 'pipe', 'pipe'] })
  procs.push(child)
  const prefix = `${COLORS[name]}[${name}]${COLORS.reset} `
  const pipe = (stream, out) => {
    let buf = ''
    stream.on('data', (chunk) => {
      buf += chunk.toString()
      const lines = buf.split(/\r?\n/)
      buf = lines.pop() ?? ''
      for (const line of lines) out.write(prefix + line + '\n')
    })
  }
  pipe(child.stdout, process.stdout)
  pipe(child.stderr, process.stderr)
  child.on('exit', (code) => {
    if (shuttingDown) return
    process.stdout.write(`${prefix}exited with code ${code}\n`)
    shutdown(code ?? 1)
  })
  return child
}

function shutdown(code = 0) {
  if (shuttingDown) return
  shuttingDown = true
  for (const p of procs) {
    try {
      if (process.platform === 'win32') spawn('taskkill', ['/pid', String(p.pid), '/t', '/f'], { shell: true })
      else p.kill('SIGINT')
    } catch { /* already gone */ }
  }
  setTimeout(() => process.exit(code), 500)
}

process.on('SIGINT', () => shutdown(0))
process.on('SIGTERM', () => shutdown(0))

run('server', 'npm run dev -w server')
run('web', 'npm run dev -w web')
