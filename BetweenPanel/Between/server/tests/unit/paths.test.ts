import { test } from 'node:test'
import assert from 'node:assert/strict'
import path from 'node:path'
import { safeJoin, sanitizeEntryName, PathTraversalError } from '../../src/lib/paths.ts'

const BASE = path.resolve('/srv/between/servers/abc')

test('safeJoin allows normal relative paths', () => {
  assert.equal(safeJoin(BASE, 'world/level.dat'), path.join(BASE, 'world', 'level.dat'))
  assert.equal(safeJoin(BASE, './plugins'), path.join(BASE, 'plugins'))
  assert.equal(safeJoin(BASE, ''), BASE)
})

test('safeJoin blocks traversal attempts', () => {
  assert.throws(() => safeJoin(BASE, '../other'), PathTraversalError)
  assert.throws(() => safeJoin(BASE, '..'), PathTraversalError)
  assert.throws(() => safeJoin(BASE, 'a/../../b'), PathTraversalError)
})

test('safeJoin treats absolute input as sandbox-relative', () => {
  // Leading slashes are stripped so "absolute" requests stay inside the root.
  assert.equal(safeJoin(BASE, '/etc/passwd'), path.join(BASE, 'etc', 'passwd'))
})

test('safeJoin normalizes backslashes (windows-style input)', () => {
  assert.equal(safeJoin(BASE, 'a\\b\\c.txt'), path.join(BASE, 'a', 'b', 'c.txt'))
  assert.throws(() => safeJoin(BASE, '..\\evil'), PathTraversalError)
})

test('sanitizeEntryName rejects dangerous archive names', () => {
  assert.equal(sanitizeEntryName('folder/file.txt'), 'folder/file.txt')
  assert.equal(sanitizeEntryName('/absolute/path'), null)
  assert.equal(sanitizeEntryName('../../etc/shadow'), null)
  assert.equal(sanitizeEntryName('a/../b'), null)
  assert.equal(sanitizeEntryName('C:\\windows\\system32'), null)
  assert.equal(sanitizeEntryName(''), null)
})
