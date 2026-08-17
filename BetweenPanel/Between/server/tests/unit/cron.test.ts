import { test } from 'node:test'
import assert from 'node:assert/strict'
import { parseCron, cronMatches, nextRun } from '../../src/lib/cron.ts'

test('parses simple expressions', () => {
  const spec = parseCron('0 4 * * *')
  assert.equal(spec.minutes.size, 1)
  assert.ok(spec.minutes.has(0))
  assert.ok(spec.hours.has(4))
  assert.equal(spec.dom.size, 31)
  assert.equal(spec.months.size, 12)
  assert.equal(spec.dow.size, 7)
})

test('parses steps, ranges and lists', () => {
  const spec = parseCron('*/15 8-10 1,15 * mon-fri')
  assert.deepEqual([...spec.minutes].sort((a, b) => a - b), [0, 15, 30, 45])
  assert.deepEqual([...spec.hours].sort((a, b) => a - b), [8, 9, 10])
  assert.deepEqual([...spec.dom].sort((a, b) => a - b), [1, 15])
  assert.deepEqual([...spec.dow].sort((a, b) => a - b), [1, 2, 3, 4, 5])
})

test('parses aliases', () => {
  assert.ok(parseCron('@daily').minutes.has(0))
  assert.ok(parseCron('@hourly').hours.size === 24)
  const weekly = parseCron('@weekly')
  assert.ok(weekly.dow.has(0) && weekly.dow.size === 1)
})

test('day-of-week 7 normalizes to sunday', () => {
  const spec = parseCron('0 0 * * 7')
  assert.ok(spec.dow.has(0))
})

test('month and weekday names', () => {
  const spec = parseCron('0 0 * jan,jul sun')
  assert.deepEqual([...spec.months].sort((a, b) => a - b), [1, 7])
  assert.ok(spec.dow.has(0))
})

test('rejects malformed expressions', () => {
  assert.throws(() => parseCron('0 4 * *'))
  assert.throws(() => parseCron('61 * * * *'))
  assert.throws(() => parseCron('* 25 * * *'))
  assert.throws(() => parseCron('bogus'))
})

test('cronMatches respects fields', () => {
  const spec = parseCron('30 4 * * *')
  assert.ok(cronMatches(spec, new Date(2026, 0, 5, 4, 30)))
  assert.ok(!cronMatches(spec, new Date(2026, 0, 5, 4, 31)))
  assert.ok(!cronMatches(spec, new Date(2026, 0, 5, 5, 30)))
})

test('vixie OR semantics when both dom and dow are restricted', () => {
  const spec = parseCron('0 0 13 * fri')
  // 2026-02-13 is a Friday → matches both; 2026-02-01 is a Sunday the 1st → neither
  assert.ok(cronMatches(spec, new Date(2026, 1, 13, 0, 0)))
  assert.ok(!cronMatches(spec, new Date(2026, 1, 1, 0, 0)))
  // 2026-01-13 is a Tuesday → dom matches, dow does not → still runs (OR)
  assert.ok(cronMatches(spec, new Date(2026, 0, 13, 0, 0)))
})

test('nextRun finds the strictly-next slot', () => {
  const spec = parseCron('0 4 * * *')
  const from = new Date(2026, 5, 10, 4, 0, 0)
  const next = nextRun(spec, from)
  assert.ok(next)
  assert.equal(next.getDate(), 11)
  assert.equal(next.getHours(), 4)
  assert.equal(next.getMinutes(), 0)
})

test('nextRun rolls over months', () => {
  const spec = parseCron('0 0 1 * *') // 1st of each month
  const from = new Date(2026, 0, 15)
  const next = nextRun(spec, from)
  assert.ok(next)
  assert.equal(next.getMonth(), 1)
  assert.equal(next.getDate(), 1)
})
