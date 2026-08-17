import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { Store } from '../../src/lib/jsonstore.ts'

interface Item {
  id: string
  name: string
  count?: number
}

test('insert / get / update / remove roundtrip', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-store-'))
  const store = new Store(dir)
  const items = store.collection<Item>('items')

  const created = items.insert({ name: 'alpha' })
  assert.ok(created.id)
  assert.equal(items.get(created.id)?.name, 'alpha')

  items.update(created.id, { count: 5 })
  assert.equal(items.get(created.id)?.count, 5)

  assert.ok(items.remove(created.id))
  assert.equal(items.get(created.id), undefined)

  store.flushAll()
  fs.rmSync(dir, { recursive: true, force: true })
})

test('data persists across store instances', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-store-'))
  {
    const store = new Store(dir)
    const items = store.collection<Item>('items')
    items.insert({ id: 'fixed-id', name: 'persisted' } as Item)
    store.flushAll()
  }
  {
    const store = new Store(dir)
    const items = store.collection<Item>('items')
    assert.equal(items.get('fixed-id')?.name, 'persisted')
  }
  fs.rmSync(dir, { recursive: true, force: true })
})

test('filter / find / removeWhere', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-store-'))
  const store = new Store(dir)
  const items = store.collection<Item>('items')
  items.insert({ name: 'a', count: 1 })
  items.insert({ name: 'b', count: 2 })
  items.insert({ name: 'c', count: 3 })

  assert.equal(items.filter((i) => (i.count ?? 0) >= 2).length, 2)
  assert.equal(items.find((i) => i.name === 'b')?.count, 2)
  const removed = items.removeWhere((i) => (i.count ?? 0) > 1)
  assert.equal(removed, 2)
  assert.equal(items.size(), 1)

  store.flushAll()
  fs.rmSync(dir, { recursive: true, force: true })
})
