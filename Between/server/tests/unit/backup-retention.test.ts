/**
 * Unit tests for the pure prune-selection behind the per-server backup
 * retention policy ("keep the last N unlocked backups"): locked backups are
 * exempt from deletion AND from the count, keep <= 0 means unlimited, and
 * the returned ids are the oldest overflow entries.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { selectBackupsToPrune } from '../../src/services/backups.ts'

const b = (id: string, createdAt: string, locked = false) => ({ id, createdAt, locked })

test('keep <= 0 or non-finite means unlimited: nothing is pruned', () => {
  const backups = [b('a', '2026-01-01'), b('b', '2026-01-02'), b('c', '2026-01-03')]
  assert.deepEqual(selectBackupsToPrune(backups, 0), [])
  assert.deepEqual(selectBackupsToPrune(backups, -1), [])
  assert.deepEqual(selectBackupsToPrune(backups, Number.NaN), [])
  assert.deepEqual(selectBackupsToPrune(backups, Number.POSITIVE_INFINITY), [])
})

test('at or below the limit nothing is pruned', () => {
  const backups = [b('a', '2026-01-01'), b('b', '2026-01-02')]
  assert.deepEqual(selectBackupsToPrune([], 2), [])
  assert.deepEqual(selectBackupsToPrune(backups, 2), [])
  assert.deepEqual(selectBackupsToPrune(backups, 3), [])
})

test('overflow returns the oldest unlocked ids, oldest first', () => {
  const backups = [b('a', '2026-01-01'), b('b', '2026-01-02'), b('c', '2026-01-03'), b('d', '2026-01-04')]
  assert.deepEqual(selectBackupsToPrune(backups, 2), ['a', 'b'])
  assert.deepEqual(selectBackupsToPrune(backups, 1), ['a', 'b', 'c'])
})

test('input order does not matter — selection sorts by createdAt', () => {
  const backups = [b('c', '2026-01-03'), b('a', '2026-01-01'), b('d', '2026-01-04'), b('b', '2026-01-02')]
  assert.deepEqual(selectBackupsToPrune(backups, 2), ['a', 'b'])
})

test('locked backups are never pruned and do not count toward N', () => {
  const backups = [
    b('old-locked', '2025-12-01', true),
    b('a', '2026-01-01'),
    b('b', '2026-01-02'),
    b('c', '2026-01-03'),
  ]
  // 3 unlocked, keep 2 → only the oldest unlocked goes; the locked one is
  // older than everything and still survives.
  assert.deepEqual(selectBackupsToPrune(backups, 2), ['a'])
  // All-locked lists never prune, regardless of N.
  const allLocked = [b('x', '2026-01-01', true), b('y', '2026-01-02', true)]
  assert.deepEqual(selectBackupsToPrune(allLocked, 1), [])
})

test('fractional keep is floored', () => {
  const backups = [b('a', '2026-01-01'), b('b', '2026-01-02'), b('c', '2026-01-03')]
  assert.deepEqual(selectBackupsToPrune(backups, 2.9), ['a'])
})
