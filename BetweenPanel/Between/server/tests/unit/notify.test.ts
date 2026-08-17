/**
 * Notifier unit tests — generic webhook URL validation plus the delivery
 * bounding invariants: an injected timeout must cap a hung receiver, and
 * stop() must abort an in-flight request (panel shutdown path).
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import os from 'node:os'
import path from 'node:path'
import { Store, type Collection } from '../../src/lib/jsonstore.ts'
import { Notifier, validateWebhookUrl } from '../../src/services/notify.ts'
import { sleep } from '../../src/lib/util.ts'
import type { PanelSettings } from '../../src/types.ts'

let dir = ''
let blackhole: http.Server
let blackholeUrl = ''
let storeSeq = 0

before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-notify-'))
  // Accepts connections but never answers — exercises the timeout/abort paths.
  blackhole = http.createServer(() => undefined)
  await new Promise<void>((resolve) => blackhole.listen(0, '127.0.0.1', resolve))
  blackholeUrl = `http://127.0.0.1:${(blackhole.address() as { port: number }).port}/hook`
})

after(() => {
  blackhole.closeAllConnections()
  blackhole.close()
  fs.rmSync(dir, { recursive: true, force: true })
})

function settingsWith(webhookUrl: string): Collection<PanelSettings> {
  const store = new Store(path.join(dir, `db-${storeSeq++}`))
  const col = store.collection<PanelSettings>('settings')
  col.insert({
    panelName: 'Unit Panel',
    defaultBackupRetention: 10,
    portRangeStart: 25565,
    portRangeEnd: 29000,
    webhookUrl,
    webhookEvents: { crash: true, power: true, backup: true },
  })
  return col
}

test('validateWebhookUrl accepts any http(s) host/port, rejects malformed URLs', () => {
  assert.equal(validateWebhookUrl('https://hooks.example.com/x'), null)
  // Private/LAN receivers are the point of a self-hosted panel — must pass.
  assert.equal(validateWebhookUrl('http://192.168.1.10:5678/webhook'), null)
  assert.equal(validateWebhookUrl('http://127.0.0.1:8080/hook'), null)
  assert.ok(validateWebhookUrl('ftp://example.com/x'))
  assert.ok(validateWebhookUrl('javascript:alert(1)'))
  assert.ok(validateWebhookUrl('not a url'))
  assert.ok(validateWebhookUrl(`https://example.com/${'a'.repeat(500)}`))
})

test('a hung receiver is bounded by the injected timeout', async () => {
  const notifier = new Notifier(settingsWith(blackholeUrl), { webhookTimeoutMs: 250 })
  const started = Date.now()
  const result = await notifier.sendTestWebhook()
  assert.equal(result.ok, false)
  assert.ok(Date.now() - started < 5000, 'request must fail promptly instead of hanging')
  notifier.stop()
})

test('stop() aborts an in-flight webhook request', async () => {
  const notifier = new Notifier(settingsWith(blackholeUrl)) // default 10s timeout
  const pending = notifier.sendTestWebhook()
  await sleep(100)
  const stopAt = Date.now()
  notifier.stop()
  const result = await pending
  assert.equal(result.ok, false)
  assert.ok(Date.now() - stopAt < 2000, 'stop() must unblock the in-flight request')
})

test('sendTestWebhook without a configured URL fails cleanly', async () => {
  const notifier = new Notifier(settingsWith(''))
  const result = await notifier.sendTestWebhook()
  assert.equal(result.ok, false)
  assert.match(String(result.error), /no webhook URL/)
  notifier.stop()
})
