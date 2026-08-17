/**
 * Exec API of the hand-rolled Docker client (web shell plumbing) against a
 * scripted fake daemon on a unix socket — mirrors docker.test.ts. Also proves
 * the hijack refactor: exec streams are RAW (Tty mode, no multiplex framing)
 * while attach keeps its demuxed behavior (covered by docker.test.ts).
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import fs from 'node:fs'
import path from 'node:path'
import { DockerClient } from '../../src/lib/docker.ts'

const unixOnly = process.platform === 'win32' ? { skip: 'unix sockets only' } : {}

function tmpSocketPath(): string {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'between-docker-exec-')), 'mock.sock')
}

test('execCreate posts a Tty /bin/sh exec and returns the exec id', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const requests: { method: string; url: string; body: string }[] = []
  const server = http.createServer((req, res) => {
    let body = ''
    req.on('data', (c) => (body += c))
    req.on('end', () => {
      requests.push({ method: req.method ?? '', url: req.url ?? '', body })
      if (req.url?.endsWith('/exec')) {
        res.statusCode = 201
        return res.end(JSON.stringify({ Id: 'exec123' }))
      }
      res.statusCode = 500
      res.end('{}')
    })
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))
  try {
    const client = new DockerClient(socketPath)
    const id = await client.execCreate('c/1', ['/bin/sh'])
    assert.equal(id, 'exec123')
    assert.equal(requests[0].method, 'POST')
    assert.equal(requests[0].url, '/containers/c%2F1/exec', 'container id must be encoded')
    const payload = JSON.parse(requests[0].body)
    assert.equal(payload.Tty, true)
    assert.equal(payload.AttachStdin, true)
    assert.equal(payload.AttachStdout, true)
    assert.equal(payload.AttachStderr, true)
    assert.deepEqual(payload.Cmd, ['/bin/sh'])
  } finally {
    server.close()
  }
})

test('execStart hijacks the upgrade, pipes RAW Tty output, forwards stdin, fires onClose', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const received: Buffer[] = []
  let requestHead = ''
  let requestBody = ''
  let daemonSide: net.Socket | null = null
  const server = net.createServer((socket) => {
    daemonSide = socket
    let buf = Buffer.alloc(0)
    const onHandshake = (chunk: Buffer) => {
      buf = Buffer.concat([buf, chunk])
      const end = buf.indexOf('\r\n\r\n')
      if (end === -1) return
      requestHead = buf.subarray(0, end).toString()
      const lenMatch = requestHead.match(/Content-Length: (\d+)/i)
      const bodyLen = lenMatch ? Number(lenMatch[1]) : 0
      if (buf.length < end + 4 + bodyLen) return
      requestBody = buf.subarray(end + 4, end + 4 + bodyLen).toString()
      const rest = buf.subarray(end + 4 + bodyLen)
      socket.off('data', onHandshake)
      socket.on('data', (d) => received.push(d))
      if (rest.length) received.push(rest)
      socket.write(
        'HTTP/1.1 101 UPGRADED\r\nContent-Type: application/vnd.docker.raw-stream\r\nConnection: Upgrade\r\nUpgrade: tcp\r\n\r\n',
      )
      // Payload deliberately shaped like a multiplex frame header + body —
      // raw (Tty) mode must deliver every byte instead of demuxing.
      socket.write(Buffer.concat([Buffer.from([1, 0, 0, 0, 0, 0, 0, 2]), Buffer.from('hi')]))
    }
    socket.on('data', onHandshake)
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))
  try {
    const client = new DockerClient(socketPath)
    const out: Buffer[] = []
    let closed = false
    const attachment = await client.execStart('exec123', {
      onData: (chunk) => out.push(chunk),
      onClose: () => {
        closed = true
      },
    })
    await new Promise((r) => setTimeout(r, 100))
    assert.match(requestHead, /^POST \/exec\/exec123\/start HTTP\/1\.1/)
    assert.match(requestHead, /Connection: Upgrade/)
    assert.match(requestHead, /Upgrade: tcp/)
    assert.match(requestHead, /Content-Type: application\/json/)
    assert.deepEqual(JSON.parse(requestBody), { Detach: false, Tty: true })
    assert.deepEqual(
      [...Buffer.concat(out)],
      [1, 0, 0, 0, 0, 0, 0, 2, ...Buffer.from('hi')],
      'Tty output must pass through byte-for-byte (no demux framing)',
    )

    assert.equal(attachment.writable, true)
    attachment.write('ls\n')
    await new Promise((r) => setTimeout(r, 50))
    assert.ok(Buffer.concat(received).toString().includes('ls\n'), 'stdin bytes reach the daemon socket')

    // Daemon closes the stream (shell exited) → onClose fires exactly then.
    assert.equal(closed, false)
    daemonSide!.destroy()
    await new Promise((r) => setTimeout(r, 100))
    assert.equal(closed, true)
    assert.equal(attachment.writable, false)
  } finally {
    server.close()
  }
})

test('execStart rejects on a non-upgrade response', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const server = http.createServer((req, res) => {
    req.resume()
    req.on('end', () => {
      res.statusCode = 409
      res.end(JSON.stringify({ message: 'container is not running' }))
    })
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))
  try {
    const client = new DockerClient(socketPath)
    await assert.rejects(() => client.execStart('deadexec', { onData: () => {}, onClose: () => {} }), /exec start failed \(HTTP 409\)/)
  } finally {
    server.close()
  }
})

test('execResize posts h/w and swallows daemon errors', unixOnly, async () => {
  const socketPath = tmpSocketPath()
  const urls: string[] = []
  const server = http.createServer((req, res) => {
    req.resume()
    req.on('end', () => {
      urls.push(req.url ?? '')
      res.statusCode = 404
      res.end(JSON.stringify({ message: 'no such exec' }))
    })
  })
  await new Promise<void>((resolve) => server.listen(socketPath, resolve))
  try {
    const client = new DockerClient(socketPath)
    await client.execResize('exec123', 40, 120)
    assert.equal(urls[0], '/exec/exec123/resize?h=40&w=120')
  } finally {
    server.close()
  }
  // Even an unreachable daemon must never surface a resize failure.
  const gone = new DockerClient(path.join(os.tmpdir(), 'between-no-such-socket.sock'))
  await gone.execResize('exec123', 40, 120)
})
