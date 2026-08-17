import { test } from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import fs from 'node:fs'
import path from 'node:path'
import { DockerClient, StreamDemuxer, computeStats, isValidImageRef, splitImageTag } from '../../src/lib/docker.ts'

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------
test('splitImageTag handles plain, tagged, registry-port and digest refs', () => {
  assert.deepEqual(splitImageTag('debian'), ['debian', 'latest'])
  assert.deepEqual(splitImageTag('eclipse-temurin:21-jre'), ['eclipse-temurin', '21-jre'])
  assert.deepEqual(splitImageTag('ghcr.io/parkervcp/yolks:java_21'), ['ghcr.io/parkervcp/yolks', 'java_21'])
  assert.deepEqual(splitImageTag('localhost:5000/img'), ['localhost:5000/img', 'latest'])
  assert.deepEqual(splitImageTag('localhost:5000/img:v2'), ['localhost:5000/img', 'v2'])
  assert.deepEqual(splitImageTag('img@sha256:abc'), ['img', 'sha256:abc'])
})

test('isValidImageRef accepts sane refs and rejects junk', () => {
  assert.equal(isValidImageRef('node:22-alpine'), true)
  assert.equal(isValidImageRef('ghcr.io/org/image:tag'), true)
  assert.equal(isValidImageRef(''), false)
  assert.equal(isValidImageRef('has space'), false)
  assert.equal(isValidImageRef('-leading-dash'), false)
  assert.equal(isValidImageRef('x'.repeat(300)), false)
})

test('StreamDemuxer reassembles fragmented multiplexed frames', () => {
  const out: { stream: string; text: string }[] = []
  const demux = new StreamDemuxer((stream, chunk) => out.push({ stream, text: chunk.toString() }))
  const frame = (type: number, payload: string) => {
    const head = Buffer.alloc(8)
    head[0] = type
    head.writeUInt32BE(Buffer.byteLength(payload), 4)
    return Buffer.concat([head, Buffer.from(payload)])
  }
  const combined = Buffer.concat([frame(1, 'hello stdout\n'), frame(2, 'oops stderr\n'), frame(1, 'more')])
  // Push byte-by-byte to prove incremental parsing works.
  for (let i = 0; i < combined.length; i++) demux.push(combined.subarray(i, i + 1))
  assert.deepEqual(out, [
    { stream: 'stdout', text: 'hello stdout\n' },
    { stream: 'stderr', text: 'oops stderr\n' },
    { stream: 'stdout', text: 'more' },
  ])
})

test('StreamDemuxer never buffers a whole oversized frame (hostile size header)', () => {
  const out: { stream: string; bytes: number }[] = []
  const demux = new StreamDemuxer((stream, chunk) => out.push({ stream, bytes: chunk.length }))
  // Header declares a 4 MiB stderr frame (> 1 MiB buffering cap) — the
  // payload must stream through in chunks instead of accumulating.
  const size = 4 * 1024 * 1024
  const head = Buffer.alloc(8)
  head[0] = 2
  head.writeUInt32BE(size, 4)
  demux.push(head)
  demux.push(Buffer.alloc(64 * 1024, 0x61))
  demux.push(Buffer.alloc(64 * 1024, 0x62))
  assert.deepEqual(
    out,
    [
      { stream: 'stderr', bytes: 64 * 1024 },
      { stream: 'stderr', bytes: 64 * 1024 },
    ],
    'payload is emitted as it arrives, not buffered',
  )
  // After the oversized frame completes, normal framing resumes.
  demux.push(Buffer.alloc(size - 128 * 1024))
  const frame = Buffer.concat([Buffer.from([1, 0, 0, 0]), Buffer.from([0, 0, 0, 2]), Buffer.from('ok')])
  demux.push(frame)
  assert.deepEqual(out[out.length - 1], { stream: 'stdout', bytes: 2 })
})

test('computeStats derives cpu pct, reclaim-adjusted memory and pids', () => {
  const sample = computeStats({
    cpu_stats: { cpu_usage: { total_usage: 2_000_000_000 }, system_cpu_usage: 10_000_000_000, online_cpus: 4 },
    precpu_stats: { cpu_usage: { total_usage: 1_000_000_000 }, system_cpu_usage: 8_000_000_000 },
    memory_stats: { usage: 512 * 1024 * 1024, stats: { inactive_file: 112 * 1024 * 1024 } },
    pids_stats: { current: 23 },
  })
  assert.ok(sample)
  assert.equal(sample.cpuPct, 200) // (1e9 / 2e9) * 4 * 100
  assert.equal(sample.memBytes, 400 * 1024 * 1024)
  assert.equal(sample.processes, 23)
  assert.equal(computeStats({}), null)
  assert.equal(computeStats(null), null)
})

// ---------------------------------------------------------------------------
// Client against a fake daemon on a unix socket (skipped on Windows)
// ---------------------------------------------------------------------------
const unixOnly = process.platform === 'win32' ? { skip: 'unix sockets only' } : {}

function tmpSocketPath(): string {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'between-docker-')), 'mock.sock')
}

test('DockerClient talks to a daemon socket: ping, version, create, kill, wait', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const requests: { method: string; url: string; body: string }[] = []
  const server = http.createServer((req, res) => {
    let body = ''
    req.on('data', (c) => (body += c))
    req.on('end', () => {
      requests.push({ method: req.method ?? '', url: req.url ?? '', body })
      if (req.url === '/_ping') return res.end('OK')
      if (req.url === '/version') return res.end(JSON.stringify({ Version: '28.0.0', ApiVersion: '1.49', Os: 'linux', Arch: 'x86_64' }))
      if (req.url?.startsWith('/containers/create')) {
        res.statusCode = 201
        return res.end(JSON.stringify({ Id: 'cafebabe' }))
      }
      if (req.url === '/containers/cafebabe/start') {
        res.statusCode = 204
        return res.end()
      }
      if (req.url?.startsWith('/containers/cafebabe/kill')) {
        res.statusCode = 204
        return res.end()
      }
      if (req.url?.startsWith('/containers/cafebabe/wait')) {
        assert.ok(req.url.includes('condition=next-exit'), 'wait must use condition=next-exit')
        // Simulate the long poll resolving with an exit code.
        setTimeout(() => res.end(JSON.stringify({ StatusCode: 137 })), 50)
        return
      }
      if (req.url === '/images/missing/json') {
        res.statusCode = 404
        return res.end(JSON.stringify({ message: 'no such image' }))
      }
      res.statusCode = 500
      res.end(JSON.stringify({ message: `unexpected ${req.method} ${req.url}` }))
    })
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))

  try {
    const client = new DockerClient(socketPath)
    assert.equal(await client.ping(), true)
    const v = await client.version()
    assert.equal(v.version, '28.0.0')
    assert.equal(await client.imageExists('missing'), false)

    const id = await client.createContainer({
      name: 'between-test',
      image: 'node:22-alpine',
      cmd: ['node', 'server.js'],
      env: { FOO: 'bar' },
      workdir: '/data',
      bind: { hostDir: '/tmp/x', containerDir: '/data' },
      ports: [
        { port: 25565, protocol: 'tcp' },
        { port: 25565, protocol: 'udp' },
      ],
      labels: { 'between.server.id': 's1' },
      memoryBytes: 512 * 1024 * 1024,
      cpus: 1.5,
      networkMode: 'bridge',
      user: '1000:1000',
    })
    assert.equal(id, 'cafebabe')
    const createReq = requests.find((r) => r.url.startsWith('/containers/create'))!
    const payload = JSON.parse(createReq.body)
    assert.equal(payload.Image, 'node:22-alpine')
    assert.deepEqual(payload.Cmd, ['node', 'server.js'])
    assert.deepEqual(payload.Env, ['FOO=bar'])
    assert.equal(payload.HostConfig.Memory, 512 * 1024 * 1024)
    assert.equal(payload.HostConfig.NanoCpus, 1_500_000_000)
    assert.equal(payload.HostConfig.Init, true)
    assert.deepEqual(payload.HostConfig.PortBindings['25565/tcp'], [{ HostPort: '25565' }])
    assert.deepEqual(payload.HostConfig.PortBindings['25565/udp'], [{ HostPort: '25565' }])
    assert.equal(payload.User, '1000:1000')

    await client.startContainer('cafebabe')
    await client.killContainer('cafebabe', 'SIGTERM')
    assert.equal(await client.waitContainer('cafebabe'), 137)
  } finally {
    server.close()
  }
})

test('DockerClient.pullImage streams ndjson progress and surfaces errors', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  let mode: 'ok' | 'fail' = 'ok'
  const server = http.createServer((req, res) => {
    req.resume()
    req.on('end', () => {
      if (!req.url?.startsWith('/images/create')) {
        res.statusCode = 500
        return res.end('{}')
      }
      if (mode === 'ok') {
        res.write(JSON.stringify({ status: 'Pulling from library/node' }) + '\n')
        res.write(JSON.stringify({ status: 'Downloading', id: 'aaa' }) + '\n')
        res.write(JSON.stringify({ status: 'Pull complete', id: 'aaa' }) + '\n')
        res.end(JSON.stringify({ status: 'Status: Downloaded newer image' }) + '\n')
      } else {
        res.write(JSON.stringify({ status: 'Pulling from library/nope' }) + '\n')
        res.end(JSON.stringify({ error: 'manifest unknown' }) + '\n')
      }
    })
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))
  try {
    const client = new DockerClient(socketPath)
    const lines: string[] = []
    await client.pullImage('node:22-alpine', (l) => lines.push(l))
    assert.ok(lines.some((l) => l.includes('Pulling from library/node')))
    assert.ok(lines.some((l) => l.includes('Pull complete aaa')))

    mode = 'fail'
    await assert.rejects(() => client.pullImage('nope:latest', () => {}), /manifest unknown/)
  } finally {
    server.close()
  }
})

test('DockerClient.attachContainer hijacks the connection and demuxes output', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const received: Buffer[] = []
  const server = net.createServer((socket) => {
    let buf = Buffer.alloc(0)
    socket.on('data', (chunk) => {
      buf = Buffer.concat([buf, chunk])
      const end = buf.indexOf('\r\n\r\n')
      if (end === -1) return
      const head = buf.subarray(0, end).toString()
      assert.match(head, /^POST \/containers\/c1\/attach/)
      const rest = buf.subarray(end + 4)
      socket.removeAllListeners('data')
      socket.on('data', (d) => received.push(d))
      if (rest.length) received.push(rest)
      socket.write('HTTP/1.1 101 UPGRADED\r\nContent-Type: application/vnd.docker.multiplexed-stream\r\nConnection: Upgrade\r\nUpgrade: tcp\r\n\r\n')
      // one stdout frame + one stderr frame
      const frame = (type: number, text: string) => {
        const head = Buffer.alloc(8)
        head[0] = type
        head.writeUInt32BE(Buffer.byteLength(text), 4)
        return Buffer.concat([head, Buffer.from(text)])
      }
      socket.write(Buffer.concat([frame(1, 'container says hi\n'), frame(2, 'warn line\n')]))
    })
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))
  try {
    const client = new DockerClient(socketPath)
    const out: { stream: string; text: string }[] = []
    let closed = false
    const attachment = await client.attachContainer('c1', {
      onData: (stream, chunk) => out.push({ stream, text: chunk.toString() }),
      onClose: () => {
        closed = true
      },
    })
    // wait for the frames to arrive
    await new Promise((r) => setTimeout(r, 100))
    assert.deepEqual(out, [
      { stream: 'stdout', text: 'container says hi\n' },
      { stream: 'stderr', text: 'warn line\n' },
    ])
    assert.equal(attachment.writable, true)
    attachment.write('stop\n')
    await new Promise((r) => setTimeout(r, 50))
    assert.ok(Buffer.concat(received).toString().includes('stop\n'))
    attachment.close()
    assert.equal(attachment.writable, false)
    assert.equal(closed, false) // explicit close does not fire onClose
  } finally {
    server.close()
  }
})

test('DockerClient rejects cleanly when the abort signal fired before the request', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const server = http.createServer((req, res) => {
    req.resume()
    req.on('end', () => setTimeout(() => res.end(JSON.stringify({ StatusCode: 0 })), 5000))
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))
  try {
    const client = new DockerClient(socketPath)
    const controller = new AbortController()
    controller.abort()
    // Regression: this used to leave an unhandled 'error' event on the
    // request (process crash) and a promise that never settled.
    await assert.rejects(() => client.waitContainer('c1', controller.signal), /aborted/)
  } finally {
    server.close()
  }
})

test('DockerClient encodes container ids into request paths', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const urls: string[] = []
  const server = http.createServer((req, res) => {
    req.resume()
    req.on('end', () => {
      urls.push(req.url ?? '')
      res.statusCode = 404
      res.end('{}')
    })
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))
  try {
    const client = new DockerClient(socketPath)
    assert.equal(await client.inspectContainer('a/b c'), null)
    assert.equal(urls[0], '/containers/a%2Fb%20c/json', 'ids must not be spliced into paths verbatim')
  } finally {
    server.close()
  }
})

test('DockerClient maps daemon errors to messages', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const server = http.createServer((req, res) => {
    req.resume()
    req.on('end', () => {
      res.statusCode = 409
      res.end(JSON.stringify({ message: 'container name already in use' }))
    })
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))
  try {
    const client = new DockerClient(socketPath)
    await assert.rejects(
      () =>
        client.createContainer({
          name: 'dup',
          image: 'x',
          cmd: ['x'],
          env: {},
          workdir: '/data',
          bind: { hostDir: '/tmp', containerDir: '/data' },
          ports: [],
          labels: {},
          networkMode: 'bridge',
        }),
      /name already in use/,
    )
  } finally {
    server.close()
  }
})

test('DockerClient rejects oversized buffered daemon responses', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const server = http.createServer((req, res) => {
    req.resume()
    req.on('end', () => {
      res.setHeader('content-length', String(16 * 1024 * 1024 + 1))
      res.write('{')
    })
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))
  try {
    const client = new DockerClient(socketPath)
    await assert.rejects(() => client.version(), /docker response too large/)
  } finally {
    server.close()
  }
})
