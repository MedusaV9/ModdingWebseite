import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { ServerInstance } from '../../src/servers/instance.ts'
import type { Blueprint, GameServer } from '../../src/types.ts'

function makeInstance(startCommand = `${process.execPath} -e "setInterval(() => {}, 1000)"`): ServerInstance {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-instance-'))
  const blueprint: Blueprint = {
    id: 'lifecycle-test',
    name: 'Lifecycle test',
    category: 'custom',
    description: '',
    platforms: [process.platform as 'linux'],
    install: [],
    startCommand,
    stop: { type: 'signal', signal: 'SIGTERM', timeoutS: 1 },
    variables: [],
  }
  const server: GameServer = {
    id: crypto.randomUUID(),
    name: 'Lifecycle test',
    blueprintId: blueprint.id,
    ownerId: 'owner',
    createdAt: new Date().toISOString(),
    dirName: path.basename(dir),
    variables: {},
    tags: [],
    autoStart: false,
    restartPolicy: { enabled: false, maxRetries: 0, backoffS: 1 },
    installed: true,
    memoryLimitMb: null,
    runtime: 'process',
  }
  return new ServerInstance(
    server,
    blueprint,
    dir,
    path.join(dir, 'steam'),
    { onStatus: () => {}, onConsole: () => {}, onResources: () => {}, onQuery: () => {} },
  )
}

test('no-marker ready timeout is tracked and cleared when the process exits', async () => {
  const inst = makeInstance()
  const state = inst as unknown as { readyTimer: NodeJS.Timeout | null }
  try {
    await inst.start()
    assert.ok(state.readyTimer, 'the fallback ready timer must be owned by the instance')
    await inst.kill()
    assert.equal(state.readyTimer, null)
  } finally {
    if (inst.active) await inst.kill()
    inst.dispose()
    fs.rmSync(inst.serverDir, { recursive: true, force: true })
  }
})

test('query refresh requests coalesce and disposal clears the owned timeout', async () => {
  const inst = makeInstance()
  let polls = 0
  const state = inst as unknown as {
    pollQuery: (() => Promise<void>) | null
    refreshQueryTimer: NodeJS.Timeout | null
  }
  state.pollQuery = async () => {
    polls++
  }
  inst.refreshQuerySoon(25)
  const first = state.refreshQueryTimer
  inst.refreshQuerySoon(25)
  assert.ok(state.refreshQueryTimer)
  assert.notEqual(state.refreshQueryTimer, first, 'the superseded timeout is replaced')
  await new Promise((resolve) => setTimeout(resolve, 60))
  assert.equal(polls, 1)
  assert.equal(state.refreshQueryTimer, null)

  inst.refreshQuerySoon(1000)
  inst.dispose()
  assert.equal(state.refreshQueryTimer, null)
  fs.rmSync(inst.serverDir, { recursive: true, force: true })
})

test(
  'asynchronous console log write errors are contained',
  { skip: process.platform !== 'linux' ? '/dev/full is Linux-specific' : false },
  async () => {
    const inst = makeInstance()
    const logDir = path.join(inst.serverDir, '.between', 'logs')
    fs.mkdirSync(logDir, { recursive: true })
    const logFile = path.join(logDir, `console-${new Date().toISOString().slice(0, 10)}.log`)
    fs.symlinkSync('/dev/full', logFile)
    const originalError = console.error
    console.error = () => {}
    try {
      inst.pushLine('system', 'this write must fail without an uncaught EventEmitter error')
      await new Promise((resolve) => setTimeout(resolve, 100))
      const state = inst as unknown as { logStream: fs.WriteStream | null }
      assert.equal(state.logStream, null)
    } finally {
      console.error = originalError
      inst.dispose()
      fs.rmSync(inst.serverDir, { recursive: true, force: true })
    }
  },
)
