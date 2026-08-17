import { test } from 'node:test'
import assert from 'node:assert/strict'
import { RingBuffer } from '../../src/lib/ringbuffer.ts'

test('starts empty', () => {
  const ring = new RingBuffer<number>(4)
  assert.equal(ring.length, 0)
  assert.equal(ring.last, undefined)
  assert.deepEqual(ring.toArray(), [])
})

test('push below capacity keeps insertion order', () => {
  const ring = new RingBuffer<number>(4)
  ring.push(1)
  ring.push(2)
  ring.push(3)
  assert.equal(ring.length, 3)
  assert.equal(ring.last, 3)
  assert.deepEqual(ring.toArray(), [1, 2, 3])
})

test('push beyond capacity drops the oldest items', () => {
  const ring = new RingBuffer<number>(3)
  for (const n of [1, 2, 3, 4, 5]) ring.push(n)
  assert.equal(ring.length, 3)
  assert.equal(ring.last, 5)
  assert.deepEqual(ring.toArray(), [3, 4, 5])
})

test('order stays correct across many wrap-arounds', () => {
  const ring = new RingBuffer<number>(5)
  for (let i = 1; i <= 23; i++) ring.push(i)
  assert.deepEqual(ring.toArray(), [19, 20, 21, 22, 23])
  assert.equal(ring.last, 23)
  assert.equal(ring.length, 5)
})

test('toArray(lastN) returns only the newest N, clamped to length', () => {
  const ring = new RingBuffer<number>(4)
  for (const n of [1, 2, 3, 4, 5, 6]) ring.push(n) // holds [3,4,5,6]
  assert.deepEqual(ring.toArray(2), [5, 6])
  assert.deepEqual(ring.toArray(4), [3, 4, 5, 6])
  assert.deepEqual(ring.toArray(99), [3, 4, 5, 6])
  assert.deepEqual(ring.toArray(0), [])
  assert.deepEqual(ring.toArray(-3), [])
})

test('toArray returns a copy, not a view', () => {
  const ring = new RingBuffer<number>(3)
  ring.push(1)
  ring.push(2)
  const copy = ring.toArray()
  copy.push(99)
  assert.deepEqual(ring.toArray(), [1, 2])
})

test('clear empties the buffer and it stays usable', () => {
  const ring = new RingBuffer<number>(3)
  for (const n of [1, 2, 3, 4]) ring.push(n)
  ring.clear()
  assert.equal(ring.length, 0)
  assert.equal(ring.last, undefined)
  assert.deepEqual(ring.toArray(), [])
  ring.push(7)
  assert.deepEqual(ring.toArray(), [7])
})

test('capacity of 1 always holds only the newest item', () => {
  const ring = new RingBuffer<string>(1)
  ring.push('a')
  ring.push('b')
  assert.equal(ring.length, 1)
  assert.deepEqual(ring.toArray(), ['b'])
})

test('rejects invalid capacities', () => {
  assert.throws(() => new RingBuffer(0))
  assert.throws(() => new RingBuffer(-1))
  assert.throws(() => new RingBuffer(2.5))
})
