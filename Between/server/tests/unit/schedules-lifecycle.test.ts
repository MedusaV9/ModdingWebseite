import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { Store } from '../../src/lib/jsonstore.ts'
import { ScheduleService } from '../../src/services/schedules.ts'
import type { BackupService } from '../../src/services/backups.ts'
import type { Notifier } from '../../src/services/notify.ts'
import type { ServerManager } from '../../src/servers/manager.ts'

test('schedule shutdown aborts waits and prevents later tasks', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-schedule-stop-'))
  let powered = false
  const instance = { status: 'offline', pushLine: () => {} }
  const manager = {
    instances: new Map([['server-1', instance]]),
    power: async () => {
      powered = true
    },
    sendCommand: () => {},
  } as unknown as ServerManager
  const backups = { create: async () => ({}) } as unknown as BackupService
  const notifier = { notify: () => {} } as unknown as Notifier
  const schedules = new ScheduleService(new Store(dir), manager, backups, notifier)
  try {
    const created = schedules.create({
      serverId: 'server-1',
      name: 'long wait',
      cron: '0 4 * * *',
      tasks: [
        { type: 'wait', seconds: 300 },
        { type: 'power', action: 'start' },
      ],
    })
    assert.ok(created.schedule)
    const execution = schedules.execute(created.schedule!.id, 'manual')
    await new Promise((resolve) => setTimeout(resolve, 20))

    const started = Date.now()
    await schedules.stop()
    await execution
    assert.ok(Date.now() - started < 500, 'shutdown must not wait for the five-minute task timeout')
    assert.equal(powered, false, 'tasks after the interrupted wait must not execute')
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})
