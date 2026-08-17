/**
 * ServerManager.pullDockerImage unit tests against a scripted fake daemon on
 * a unix socket: progress streaming into the console, precondition guards,
 * the install/update concurrency guard and the delete-aborts-pull wiring.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'
import os from 'node:os'
import fs from 'node:fs'
import path from 'node:path'
import { Store } from '../../src/lib/jsonstore.ts'
import { BlueprintRegistry } from '../../src/blueprints/registry.ts'
import { SteamCmdManager } from '../../src/steam/steamcmd.ts'
import { DockerService } from '../../src/services/docker.ts'
import { ServerManager } from '../../src/servers/manager.ts'
import type { ConsoleLine, GameServer } from '../../src/types.ts'

const unixOnly = process.platform === 'win32' ? { skip: 'unix sockets only' } : {}

interface PullDaemonOptions {
  /** Hold the pull stream open until release() is called. */
  hold?: boolean
  /** Final global status line of the pull stream (read per request). */
  finalStatus?: string
  /** End the pull stream with an ndjson error object instead. */
  failPull?: boolean
}

/** Minimal scripted docker daemon: images never exist, pulls stream ndjson. */
function fakeDaemon(opts: PullDaemonOptions = {}) {
  const socketPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'between-pull-daemon-')), 'mock.sock')
  const requests: { method: string; url: string }[] = []
  let releasePull: (() => void) | null = null
  const server = http.createServer((req, res) => {
    req.resume()
    req.on('end', () => {
      const url = req.url ?? ''
      requests.push({ method: req.method ?? '', url })
      if (url === '/_ping') return res.end('OK')
      if (url === '/version')
        return res.end(JSON.stringify({ Version: '28.0.0', ApiVersion: '1.49', Os: 'linux', Arch: 'x86_64' }))
      if (url.startsWith('/containers/json')) return res.end('[]')
      if (url.startsWith('/images/create')) {
        res.write(JSON.stringify({ status: 'Pulling from library/node' }) + '\n')
        res.write(JSON.stringify({ status: 'Downloading', id: 'aaa' }) + '\n')
        res.write(JSON.stringify({ status: 'Pull complete', id: 'aaa' }) + '\n')
        const finish = () => {
          if (opts.failPull) res.end(JSON.stringify({ error: 'manifest unknown' }) + '\n')
          else res.end(JSON.stringify({ status: opts.finalStatus ?? 'Status: Downloaded newer image for node:22-alpine' }) + '\n')
        }
        if (opts.hold) releasePull = finish
        else finish()
        return
      }
      if (url.startsWith('/images/')) {
        res.statusCode = 404
        return res.end(JSON.stringify({ message: 'no such image' }))
      }
      if (req.method === 'DELETE') {
        res.statusCode = 204
        return res.end()
      }
      res.statusCode = 500
      res.end('{}')
    })
  })
  const listen = new Promise<void>((resolve) => server.listen(socketPath, resolve))
  return { socketPath, requests, listen, release: () => releasePull?.(), close: () => server.close() }
}

function makeManager(socketPath: string): { manager: ServerManager; lines: ConsoleLine[] } {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-pull-'))
  const store = new Store(path.join(dataDir, 'db'))
  const lines: ConsoleLine[] = []
  const manager = new ServerManager(
    store,
    new BlueprintRegistry(),
    new SteamCmdManager(path.join(dataDir, 'steamcmd')),
    dataDir,
    {
      onStatus: () => {},
      onConsole: (_id, line) => lines.push(line),
      onResources: () => {},
      onQuery: () => {},
    },
    new DockerService(socketPath),
  )
  return { manager, lines }
}

/** Seed an already-installed demo-echo server (docker image: node:22-alpine). */
function seedServer(manager: ServerManager, runtime: 'docker' | 'process'): string {
  const id = crypto.randomUUID()
  manager.servers.insert({
    id,
    name: 'Pull Test',
    blueprintId: 'demo-echo',
    ownerId: 'u1',
    createdAt: new Date().toISOString(),
    dirName: `pull-${id.slice(0, 8)}`,
    variables: { SERVER_PORT: 27777 },
    tags: [],
    autoStart: false,
    restartPolicy: { enabled: false, maxRetries: 3, backoffS: 10 },
    installed: true,
    installedAt: new Date().toISOString(),
    memoryLimitMb: null,
    runtime,
  } as GameServer)
  return id
}

test('pullDockerImage streams throttled progress as install lines and reports the outcome', unixOnly, async () => {
  const opts: PullDaemonOptions = {}
  const daemon = fakeDaemon(opts)
  await daemon.listen
  const { manager, lines } = makeManager(daemon.socketPath)
  const id = seedServer(manager, 'docker')
  manager.boot()
  try {
    await manager.pullDockerImage(id)
    const pullLines = lines.filter((l) => l.stream === 'install')
    assert.ok(pullLines.some((l) => l.line.includes('Pulling image node:22-alpine')), 'start line is pushed')
    assert.ok(pullLines.some((l) => l.line.includes('docker: Pulling from library/node')), 'daemon progress is forwarded')
    assert.ok(pullLines.some((l) => l.line.includes('docker: Pull complete aaa')), 'per-layer transitions are forwarded')
    assert.ok(pullLines.some((l) => l.line.includes('Image node:22-alpine updated.')), 'a newer image reports as updated')
    assert.equal(manager.instance(id).installController, null, 'the guard is released afterwards')

    // A second pull works (guard cleared) and reports "up to date".
    opts.finalStatus = 'Status: Image is up to date for node:22-alpine'
    await manager.pullDockerImage(id)
    assert.ok(lines.some((l) => l.line.includes('Image node:22-alpine is up to date.')))
  } finally {
    manager.instance(id).dispose()
    daemon.close()
  }
})

test('pullDockerImage throws for a process-runtime server', unixOnly, async () => {
  const daemon = fakeDaemon()
  await daemon.listen
  const { manager } = makeManager(daemon.socketPath)
  const id = seedServer(manager, 'process')
  manager.boot()
  try {
    await assert.rejects(() => manager.pullDockerImage(id), /does not use the docker runtime/)
    assert.ok(!daemon.requests.some((r) => r.url.startsWith('/images/create')), 'no pull may be attempted')
  } finally {
    manager.instance(id).dispose()
    daemon.close()
  }
})

test('pullDockerImage throws when no image is configured', unixOnly, async () => {
  const daemon = fakeDaemon()
  await daemon.listen
  const { manager } = makeManager(daemon.socketPath)
  const id = seedServer(manager, 'docker')
  manager.boot()
  const inst = manager.instance(id)
  // Strip the blueprint default so neither an override nor a default exists.
  inst.blueprint = { ...inst.blueprint, docker: undefined }
  try {
    await assert.rejects(() => manager.pullDockerImage(id), /no docker image configured/)
    assert.ok(!daemon.requests.some((r) => r.url.startsWith('/images/create')), 'no pull may be attempted')
  } finally {
    inst.dispose()
    daemon.close()
  }
})

test('a running pull blocks concurrent pulls and installs, then releases the guard', unixOnly, async () => {
  const daemon = fakeDaemon({ hold: true })
  await daemon.listen
  const { manager } = makeManager(daemon.socketPath)
  const id = seedServer(manager, 'docker')
  manager.boot()
  try {
    const first = manager.pullDockerImage(id)
    // The guard is claimed synchronously — concurrent flows are refused.
    await assert.rejects(() => manager.pullDockerImage(id), /already running/)
    await assert.rejects(() => manager.reinstall(id), /already running/)
    // Wait until the pull request is actually in flight, then let it finish.
    const start = Date.now()
    while (!daemon.requests.some((r) => r.url.startsWith('/images/create')) && Date.now() - start < 5000)
      await new Promise((r) => setTimeout(r, 20))
    daemon.release()
    await first
    assert.equal(manager.instance(id).installController, null, 'the guard is released afterwards')
    assert.equal(manager.instance(id).installPromise, null)
  } finally {
    manager.instance(id).dispose()
    daemon.close()
  }
})

test('deleting the server aborts an in-flight pull without resurrecting files', unixOnly, async () => {
  const daemon = fakeDaemon({ hold: true })
  await daemon.listen
  const { manager, lines } = makeManager(daemon.socketPath)
  const id = seedServer(manager, 'docker')
  manager.boot()
  const dirName = manager.servers.get(id)!.dirName
  try {
    const pull = manager.pullDockerImage(id)
    const start = Date.now()
    while (!daemon.requests.some((r) => r.url.startsWith('/images/create')) && Date.now() - start < 5000)
      await new Promise((r) => setTimeout(r, 20))
    await manager.remove(id)
    // The abort path resolves silently — no failure line, no completion line.
    await pull
    assert.ok(!lines.some((l) => l.line.includes('Image pull failed')), 'an aborted pull is not an error')
    assert.ok(!lines.some((l) => l.line.includes('updated.')), 'an aborted pull never reports completion')
    assert.equal(manager.instances.has(id), false)
    await new Promise((r) => setTimeout(r, 100))
    assert.equal(fs.existsSync(path.join(manager.serversRoot, dirName)), false, 'the server dir must stay deleted')
  } finally {
    daemon.close()
  }
})

test('a failing pull pushes an error line and rethrows', unixOnly, async () => {
  const daemon = fakeDaemon({ failPull: true })
  await daemon.listen
  const { manager, lines } = makeManager(daemon.socketPath)
  const id = seedServer(manager, 'docker')
  manager.boot()
  try {
    await assert.rejects(() => manager.pullDockerImage(id), /manifest unknown/)
    assert.ok(lines.some((l) => l.stream === 'install' && l.line.includes('Image pull failed') && l.line.includes('manifest unknown')))
    assert.equal(manager.instance(id).installController, null, 'the guard is released after a failure')
  } finally {
    manager.instance(id).dispose()
    daemon.close()
  }
})
