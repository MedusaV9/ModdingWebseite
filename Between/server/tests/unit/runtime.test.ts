/**
 * Docker runtime lifecycle regression tests against a scripted fake daemon on
 * a unix socket. These pin down race conditions that are hard to hit with a
 * real daemon: containers that exit before the start call returns, containers
 * that die during re-adoption, and aborts landing mid-spawn.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'
import os from 'node:os'
import fs from 'node:fs'
import path from 'node:path'
import { DockerClient } from '../../src/lib/docker.ts'
import { DockerService } from '../../src/services/docker.ts'
import { ServerInstance } from '../../src/servers/instance.ts'
import { removeInstallLeftovers, spawnDockerHandle } from '../../src/servers/runtime.ts'
import type { Blueprint, ConsoleLine, GameServer } from '../../src/types.ts'

const unixOnly = process.platform === 'win32' ? { skip: 'unix sockets only' } : {}

function tmpSocketPath(): string {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'between-runtime-')), 'mock.sock')
}

interface FakeDaemonOptions {
  /** Called when the start POST arrives; return the delay before its 204. */
  onStart?: () => void
  /** ms before the create POST answers (default 0). */
  createDelayMs?: number
  /** ms before the wait long-poll answers after being armed (default: on stop-signal only). */
  waitExitCode?: number
  /** answer the wait long-poll immediately with waitExitCode. */
  waitImmediately?: boolean
  /** containers/json (list) response body. */
  listResponse?: unknown[]
  /** ms before the logs endpoint answers (default 0). */
  logsDelayMs?: number
  /** Fail the first wait long-poll (HTTP 500), then hold subsequent ones open; /start won't end the wait. */
  failWaitThenHold?: boolean
  /** Fail the wait long-poll AND report the container as gone (404) on inspect. */
  failWaitGone?: boolean
}

/** Minimal scripted docker daemon good enough for client + instance tests. */
function fakeDaemon(opts: FakeDaemonOptions) {
  const socketPath = tmpSocketPath()
  const requests: { method: string; url: string }[] = []
  let waitRes: http.ServerResponse | null = null
  let waitCalls = 0
  const server = http.createServer((req, res) => {
    req.resume()
    req.on('end', () => {
      const url = req.url ?? ''
      requests.push({ method: req.method ?? '', url })
      if (url === '/_ping') return res.end('OK')
      if (url === '/version')
        return res.end(JSON.stringify({ Version: '28.0.0', ApiVersion: '1.49', Os: 'linux', Arch: 'x86_64' }))
      if (url.startsWith('/images/')) return res.end('{}') // every image exists
      if (url.startsWith('/containers/json')) return res.end(JSON.stringify(opts.listResponse ?? []))
      if (url === '/containers/c1/json') {
        if (opts.failWaitGone) {
          res.statusCode = 404
          return res.end(JSON.stringify({ message: 'no such container' }))
        }
        return res.end(
          JSON.stringify({ Id: 'c1', State: { Status: 'running', Running: true, ExitCode: 0, StartedAt: new Date().toISOString() } }),
        )
      }
      if (url.startsWith('/containers/create')) {
        setTimeout(() => {
          res.statusCode = 201
          res.end(JSON.stringify({ Id: 'c1' }))
        }, opts.createDelayMs ?? 0)
        return
      }
      if (url.startsWith('/containers/c1/wait')) {
        waitCalls++
        // Simulate a dropped event stream: the first long-poll errors out.
        if ((opts.failWaitThenHold || opts.failWaitGone) && waitCalls === 1) {
          res.statusCode = 500
          return res.end(JSON.stringify({ message: 'connection reset' }))
        }
        waitRes = res
        if (opts.waitImmediately) setTimeout(() => waitRes?.end(JSON.stringify({ StatusCode: opts.waitExitCode ?? 0 })), 10)
        return
      }
      if (url.startsWith('/containers/c1/start')) {
        opts.onStart?.()
        // Simulate an instantly-exiting workload: the daemon reports the exit
        // (wait long-poll) before the start POST returns — unless the test
        // wants the container to keep running past a failed wait.
        if (!opts.failWaitThenHold && !opts.failWaitGone)
          waitRes?.end(JSON.stringify({ StatusCode: opts.waitExitCode ?? 0 }))
        setTimeout(() => {
          res.statusCode = 204
          res.end()
        }, 50)
        return
      }
      if (url.startsWith('/containers/c1/logs')) {
        setTimeout(() => res.end(), opts.logsDelayMs ?? 0) // empty backlog
        return
      }
      if (url.startsWith('/containers/c1/stats')) return // held open
      if (req.method === 'DELETE') {
        res.statusCode = 204
        return res.end()
      }
      res.statusCode = 500
      res.end('{}')
    })
  })
  server.on('upgrade', (_req, socket) => {
    socket.write('HTTP/1.1 101 UPGRADED\r\nConnection: Upgrade\r\nUpgrade: tcp\r\n\r\n')
  })
  const listen = new Promise<void>((resolve) => server.listen(socketPath, resolve))
  return { socketPath, requests, listen, close: () => server.close() }
}

const BLUEPRINT: Blueprint = {
  id: 'demo',
  name: 'Demo',
  category: 'custom',
  description: '',
  platforms: ['linux'],
  install: [],
  startCommand: 'run',
  stop: { type: 'signal', signal: 'SIGTERM' },
  variables: [],
  docker: { image: 'alpine:3' },
}

function gameServer(): GameServer {
  return {
    id: 's1',
    name: 'S1',
    blueprintId: 'demo',
    ownerId: 'u1',
    createdAt: new Date().toISOString(),
    dirName: 's1-abcd1234',
    variables: {},
    tags: [],
    autoStart: false,
    restartPolicy: { enabled: false, maxRetries: 3, backoffS: 10 },
    installed: true,
    memoryLimitMb: null,
    runtime: 'docker',
  } as GameServer
}

function makeInstance(socketPath: string): { inst: ServerInstance; lines: ConsoleLine[] } {
  const serverDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-runtime-srv-'))
  const lines: ConsoleLine[] = []
  const inst = new ServerInstance(
    gameServer(),
    BLUEPRINT,
    serverDir,
    path.join(serverDir, 'steam'),
    {
      onStatus: () => {},
      onConsole: (_i, line) => lines.push(line),
      onResources: () => {},
      onQuery: () => {},
    },
    new DockerService(socketPath),
  )
  return { inst, lines }
}

test('a container that exits before start() returns leaves no zombie handle', unixOnly, async () => {
  const daemon = fakeDaemon({ waitExitCode: 1 })
  await daemon.listen
  const { inst, lines } = makeInstance(daemon.socketPath)
  try {
    await inst.start()
    // Give the buffered exit a beat to settle through timers/microtasks.
    await new Promise((r) => setTimeout(r, 200))
    assert.equal(inst.status, 'crashed', 'fast exit must be observed as a crash')
    assert.equal(inst.active, false, 'no dead handle may stay installed')
    assert.equal(lines.filter((l) => l.line.includes('exited')).length, 1, 'exit is reported exactly once')
  } finally {
    inst.dispose()
    daemon.close()
  }
})

test('adopting a container that dies during adoption leaves no zombie handle', unixOnly, async () => {
  const daemon = fakeDaemon({
    waitImmediately: true,
    waitExitCode: 137,
    logsDelayMs: 100, // widens the window between wait resolving and adoption finishing
    listResponse: [
      { Id: 'c1', Names: ['/between-s1-abcd1234'], State: 'running', Status: 'Up', Labels: {}, Image: 'alpine:3' },
    ],
  })
  await daemon.listen
  const { inst } = makeInstance(daemon.socketPath)
  try {
    const adopted = await inst.tryReattachDocker()
    assert.equal(adopted, true, 'the running container is adopted first')
    await new Promise((r) => setTimeout(r, 300))
    assert.notEqual(inst.status, 'running', 'a dead container must not stay "running"')
    assert.equal(inst.active, false, 'no dead handle may stay installed')
  } finally {
    inst.dispose()
    daemon.close()
  }
})

test('abort during spawn removes the created container and rejects', unixOnly, async () => {
  const daemon = fakeDaemon({ createDelayMs: 100 })
  await daemon.listen
  const controller = new AbortController()
  setTimeout(() => controller.abort(), 30) // lands while create is in flight
  try {
    await assert.rejects(
      () =>
        spawnDockerHandle({
          client: new DockerClient(daemon.socketPath),
          serverId: 's1',
          containerName: 'between-s1',
          image: 'alpine:3',
          argv: ['run'],
          env: {},
          hostDir: '/tmp/x',
          ports: [],
          networkMode: 'bridge',
          signal: controller.signal,
          events: { onData: () => {}, onSystem: () => {}, onExit: () => {} },
        }),
      /aborted/,
    )
    await new Promise((r) => setTimeout(r, 100))
    assert.ok(
      daemon.requests.some((r) => r.method === 'DELETE' && r.url.startsWith('/containers/c1')),
      'the half-created container must be removed',
    )
    assert.ok(
      !daemon.requests.some((r) => r.url.startsWith('/containers/c1/start')),
      'an aborted spawn must not start the container',
    )
  } finally {
    daemon.close()
  }
})

test('a dropped event stream does NOT kill a container that is still running', unixOnly, async () => {
  // The wait long-poll fails once, but the container is still up: the handle
  // must re-attach and keep watching instead of reporting a crash.
  const daemon = fakeDaemon({ failWaitThenHold: true })
  await daemon.listen
  const { inst, lines } = makeInstance(daemon.socketPath)
  try {
    await inst.start()
    await new Promise((r) => setTimeout(r, 400))
    assert.equal(inst.active, true, 'the still-running container must stay attached')
    assert.notEqual(inst.status, 'crashed', 'a transient wait failure must not look like a crash')
    assert.ok(
      lines.some((l) => l.line.includes('still running, re-attaching')),
      'the re-attach must be reported',
    )
    assert.equal(lines.filter((l) => l.line.includes('exited')).length, 0, 'no exit may be reported')
    // A second wait long-poll (post re-attach) proves watching resumed.
    assert.ok(daemon.requests.filter((r) => r.url.startsWith('/containers/c1/wait')).length >= 2)
  } finally {
    inst.dispose()
    daemon.close()
  }
})

test('a dropped event stream on a vanished container reports the exit', unixOnly, async () => {
  const daemon = fakeDaemon({ failWaitGone: true })
  await daemon.listen
  const { inst, lines } = makeInstance(daemon.socketPath)
  try {
    await inst.start()
    await new Promise((r) => setTimeout(r, 400))
    assert.equal(inst.active, false, 'a gone container must release its handle')
    assert.equal(inst.status, 'crashed', 'a vanished container is an abnormal exit')
    assert.equal(lines.filter((l) => l.line.includes('exited')).length, 1, 'exit reported exactly once')
  } finally {
    inst.dispose()
    daemon.close()
  }
})

test('removeInstallLeftovers force-removes every install-labelled container', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const requests: string[] = []
  const server = http.createServer((req, res) => {
    req.resume()
    req.on('end', () => {
      requests.push(`${req.method} ${req.url}`)
      if (req.url?.startsWith('/containers/json')) {
        const filters = decodeURIComponent(req.url)
        assert.ok(filters.includes('between.install=1'), 'must filter by the install label')
        return res.end(
          JSON.stringify([
            { Id: 'i1', Names: ['/between-install-a'], State: 'running', Status: 'Up', Labels: {}, Image: 'x' },
            { Id: 'i2', Names: ['/between-install-b'], State: 'exited', Status: 'Exited', Labels: {}, Image: 'x' },
          ]),
        )
      }
      res.statusCode = 204
      res.end()
    })
  })
  await new Promise<void>((r) => server.listen(socketPath, r))
  try {
    await removeInstallLeftovers(new DockerClient(socketPath))
    assert.ok(requests.some((r) => r.startsWith('DELETE /containers/i1')))
    assert.ok(requests.some((r) => r.startsWith('DELETE /containers/i2')))
  } finally {
    server.close()
  }
})
