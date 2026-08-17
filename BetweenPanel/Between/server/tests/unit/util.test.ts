import { test } from 'node:test'
import assert from 'node:assert/strict'
import { clamp, humanBytes, substituteVars, sanitizeLine, isValidName, slugify, pick } from '../../src/lib/util.ts'

test('clamp', () => {
  assert.equal(clamp(5, 0, 10), 5)
  assert.equal(clamp(-5, 0, 10), 0)
  assert.equal(clamp(15, 0, 10), 10)
})

test('humanBytes', () => {
  assert.equal(humanBytes(0), '0 B')
  assert.equal(humanBytes(1024), '1.0 KiB')
  assert.equal(humanBytes(1536), '1.5 KiB')
  assert.ok(humanBytes(3 * 1024 * 1024 * 1024).includes('GiB'))
})

test('substituteVars replaces all placeholders', () => {
  const result = substituteVars('java -Xmx{{MEM}}M -p {{PORT}} {{PORT}}', { MEM: 2048, PORT: 25565 })
  assert.equal(result, 'java -Xmx2048M -p 25565 25565')
})

test('substituteVars leaves unknown placeholders intact', () => {
  assert.equal(substituteVars('{{UNKNOWN}}', {}), '{{UNKNOWN}}')
})

test('substituteVars handles booleans', () => {
  assert.equal(substituteVars('pvp={{PVP}}', { PVP: false }), 'pvp=false')
})

test('sanitizeLine strips control chars and caps length', () => {
  assert.equal(sanitizeLine('ok\u0007bell'), 'okbell')
  assert.equal(sanitizeLine('x'.repeat(5000)).length, 4001) // 4000 chars + ellipsis
  // ANSI colors must survive (used by the console renderer)
  assert.ok(sanitizeLine('\u001b[32mgreen\u001b[0m').includes('\u001b[32m'))
})

test('isValidName', () => {
  assert.ok(isValidName('My Server 1'))
  assert.ok(!isValidName(''))
  assert.ok(!isValidName(' '.repeat(3)))
  assert.ok(!isValidName('x'.repeat(100)))
})

test('slugify', () => {
  assert.equal(slugify('My Cool Server!'), 'my-cool-server')
  assert.equal(slugify('  Ümläute & Co  '), 'ml-ute-co')
  assert.equal(slugify('!!!'), 'server') // falls back to something non-empty
})

test('pick', () => {
  assert.deepEqual(pick({ a: 1, b: 2, c: 3 }, ['a', 'c']), { a: 1, c: 3 })
})
