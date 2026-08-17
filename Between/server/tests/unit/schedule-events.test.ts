import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { Store } from '../../src/lib/jsonstore.ts'
import { ScheduleService, diffPlayerEvents, type PlayerTrack } from '../../src/services/schedules.ts'
import type { BackupService } from '../../src/services/backups.ts'
import type { Notifier } from '../../src/services/notify.ts'
import type { ServerManager } from '../../src/servers/manager.ts'
import type { QueryResult } from '../../src/types.ts'

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

function makeService(dir: string, commands: string[]) {
  const instance = {
    status: 'running',
    server: { name: 'Mock Server' },
    lastQuery: { online: true, playersOnline: 2, playersMax: 8, ts: Date.now() },
    pushLine: () => {},
  }
  const manager = {
    instances: new Map([['server-1', instance]]),
    servers: { get: () => undefined },
    power: async () => {},
    sendCommand: (_id: string, command: string) => {
      commands.push(command)
    },
  } as unknown as ServerManager
  const backups = { create: async () => ({}) } as unknown as BackupService
  const notifier = { notify: () => {} } as unknown as Notifier
  return { service: new ScheduleService(new Store(dir), manager, backups, notifier), instance }
}

test('event trigger fires on matching status change, renders templates, and debounces repeats', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-schedule-events-'))
  const commands: string[] = []
  const { service, instance } = makeService(dir, commands)
  try {
    const created = service.create({
      serverId: 'server-1',
      name: 'on crash',
      trigger: { type: 'event', event: 'server.crashed' },
      tasks: [{ type: 'command', command: 'say {server} is {state} ({players}/{maxPlayers}) u={user} n={node} x={nope}' }],
    })
    assert.ok(created.schedule, created.problems.join('; '))
    assert.deepEqual(created.schedule!.trigger, { type: 'event', event: 'server.crashed' })
    assert.equal(service.nextRunOf(created.schedule!.id), null, 'event schedules have no cron next-run')

    // Non-matching events do nothing.
    service.handleStatusChange('server-1', 'running', 'starting')
    service.handleStatusChange('server-1', 'offline', 'running')
    await sleep(20)
    assert.equal(commands.length, 0)

    instance.status = 'crashed'
    service.handleStatusChange('server-1', 'crashed', 'running')
    await sleep(20)
    assert.equal(commands.length, 1)
    assert.equal(commands[0], 'say Mock Server is crashed (2/8) u= n=local x={nope}')

    // Crash-loop guard: an immediate second crash is debounced (30s window).
    service.handleStatusChange('server-1', 'crashed', 'running')
    await sleep(20)
    assert.equal(commands.length, 1, 'second event within the window must not run')

    const runs = service.schedules.get(created.schedule!.id)!.lastRuns
    assert.equal(runs.length, 1)
    assert.equal(runs[0].ok, true)
    assert.equal(runs[0].source, 'event:server.crashed')

    // Disabled schedules never fire.
    service.update(created.schedule!.id, { enabled: false })
    service.handleStatusChange('server-2', 'crashed', 'running')
    await sleep(20)
    assert.equal(commands.length, 1)
  } finally {
    await service.stop()
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

test('events never fire for unknown/remote server ids and reject unknown names', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-schedule-remote-'))
  const commands: string[] = []
  const { service } = makeService(dir, commands)
  try {
    const created = service.create({
      serverId: 'remote-mirror-1', // no local instance in the manager
      name: 'remote',
      trigger: { type: 'event', event: 'server.running' },
      tasks: [{ type: 'command', command: 'say hi' }],
    })
    assert.ok(created.schedule)
    service.handleStatusChange('remote-mirror-1', 'running', 'starting')
    await sleep(20)
    assert.equal(commands.length, 0, 'no local instance → event must be dropped')

    const bad = service.create({
      serverId: 'server-1',
      name: 'bad',
      trigger: { type: 'event', event: 'server.exploded' },
      tasks: [{ type: 'command', command: 'say hi' }],
    })
    assert.equal(bad.schedule, undefined)
    assert.match(bad.problems.join('; '), /unknown event/)

    const badType = service.create({
      serverId: 'server-1',
      name: 'bad2',
      trigger: { type: 'lunar-phase' },
      tasks: [{ type: 'command', command: 'say hi' }],
    })
    assert.match(badType.problems.join('; '), /unknown type/)
  } finally {
    await service.stop()
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

test('player.joined fires from a query diff with the player name in {user}', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-schedule-players-'))
  const commands: string[] = []
  const { service, instance } = makeService(dir, commands)
  try {
    const created = service.create({
      serverId: 'server-1',
      name: 'welcome',
      trigger: { type: 'event', event: 'player.joined' },
      tasks: [{ type: 'command', command: 'say Welcome {user}!' }],
    })
    assert.ok(created.schedule)
    // Baseline: server reports running (empty room), then a poll sees Steve.
    instance.status = 'running'
    service.handleStatusChange('server-1', 'running', 'starting')
    service.handleQueryResult('server-1', { online: true, playersOnline: 1, players: [{ name: 'Steve' }], ts: Date.now() })
    await sleep(20)
    assert.deepEqual(commands, ['say Welcome Steve!'])
  } finally {
    await service.stop()
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

// ---------------------------------------------------------------------------
// Pure diff logic
// ---------------------------------------------------------------------------
const track = (names: string[], namesValid: boolean, count: number): PlayerTrack => ({ names: new Set(names), namesValid, count })
const q = (partial: Partial<QueryResult>): QueryResult => ({ online: true, ts: 0, ...partial })

test('diffPlayerEvents: name diff when the roster is complete', () => {
  const r1 = diffPlayerEvents(track([], true, 0), q({ playersOnline: 2, players: [{ name: 'Steve' }, { name: 'Alex' }] }))
  assert.deepEqual(r1.events, [
    { event: 'player.joined', user: 'Steve' },
    { event: 'player.joined', user: 'Alex' },
  ])
  assert.equal(r1.next.count, 2)

  const r2 = diffPlayerEvents(r1.next, q({ playersOnline: 1, players: [{ name: 'Alex' }] }))
  assert.deepEqual(r2.events, [{ event: 'player.left', user: 'Steve' }])
})

test('diffPlayerEvents: count delta (no names) yields anonymous events', () => {
  const r1 = diffPlayerEvents(track([], true, 0), q({ playersOnline: 3 }))
  assert.deepEqual(r1.events, [{ event: 'player.joined' }])
  const r2 = diffPlayerEvents(r1.next, q({ playersOnline: 1 }))
  assert.deepEqual(r2.events, [{ event: 'player.left' }])
  const r3 = diffPlayerEvents(r2.next, q({ playersOnline: 1 }))
  assert.deepEqual(r3.events, [])
})

test('diffPlayerEvents: partial name sample falls back to count delta', () => {
  // 5 online but only a 2-name sample → must not fabricate name-based leaves.
  const prev = track(['Steve', 'Alex', 'Kai'], true, 3)
  const r = diffPlayerEvents(prev, q({ playersOnline: 5, players: [{ name: 'Steve' }, { name: 'Noor' }] }))
  assert.deepEqual(r.events, [{ event: 'player.joined' }])
  assert.equal(r.next.namesValid, false)

  // Roster completes again → adopted silently (no mass-join), diffing resumes.
  const r2 = diffPlayerEvents(r.next, q({ playersOnline: 5, players: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }, { name: 'e' }] }))
  assert.deepEqual(r2.events, [])
  assert.equal(r2.next.namesValid, true)
  const r3 = diffPlayerEvents(r2.next, q({ playersOnline: 4, players: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }] }))
  assert.deepEqual(r3.events, [{ event: 'player.left', user: 'e' }])
})

test('diffPlayerEvents: a result without any player data changes nothing', () => {
  const prev = track(['Steve'], true, 1)
  const r = diffPlayerEvents(prev, q({}))
  assert.deepEqual(r.events, [])
  assert.equal(r.next, prev)
})
