/**
 * Tiny embedded JSON document store.
 *
 * Design goals: zero native dependencies (works identically on Linux and
 * Windows), atomic persistence (tmp file + rename), debounced writes, and a
 * simple typed collection API. The panel is a single process, so in-memory
 * maps with write-behind persistence are safe and fast.
 */
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'

export interface Doc {
  id: string
}

export function newId(): string {
  return crypto.randomUUID()
}

const FLUSH_DELAY_MS = 150

export class Collection<T extends Doc> {
  private items = new Map<string, T>()
  private timer: ReturnType<typeof setTimeout> | null = null
  private dirty = false

  constructor(private file: string) {
    this.load()
  }

  private load() {
    try {
      if (fs.existsSync(this.file)) {
        const raw = JSON.parse(fs.readFileSync(this.file, 'utf8')) as T[]
        for (const doc of raw) this.items.set(doc.id, doc)
      }
    } catch (err) {
      // Corrupt file: keep a copy for forensics, start fresh rather than crash.
      try {
        fs.copyFileSync(this.file, `${this.file}.corrupt-${Date.now()}`)
      } catch { /* ignore */ }
      console.error(`[store] failed to load ${this.file}:`, err)
    }
  }

  all(): T[] {
    return [...this.items.values()]
  }

  size(): number {
    return this.items.size
  }

  get(id: string): T | undefined {
    return this.items.get(id)
  }

  find(pred: (doc: T) => boolean): T | undefined {
    for (const doc of this.items.values()) if (pred(doc)) return doc
    return undefined
  }

  filter(pred: (doc: T) => boolean): T[] {
    return this.all().filter(pred)
  }

  insert(doc: Omit<T, 'id'> & { id?: string }): T {
    const full = { ...doc, id: doc.id ?? newId() } as T
    if (this.items.has(full.id)) throw new Error(`duplicate id ${full.id}`)
    this.items.set(full.id, full)
    this.schedule()
    return full
  }

  /** Replace or merge fields on an existing doc. Returns the updated doc. */
  update(id: string, patch: Partial<T> | ((doc: T) => void)): T | undefined {
    const doc = this.items.get(id)
    if (!doc) return undefined
    if (typeof patch === 'function') patch(doc)
    else Object.assign(doc, patch)
    this.schedule()
    return doc
  }

  remove(id: string): boolean {
    const ok = this.items.delete(id)
    if (ok) this.schedule()
    return ok
  }

  removeWhere(pred: (doc: T) => boolean): number {
    let n = 0
    for (const [id, doc] of this.items) {
      if (pred(doc)) {
        this.items.delete(id)
        n++
      }
    }
    if (n > 0) this.schedule()
    return n
  }

  private schedule() {
    this.dirty = true
    if (this.timer) return
    this.timer = setTimeout(() => {
      this.timer = null
      // A timer callback has no error boundary — a failed write (ENOSPC,
      // EACCES, …) must not crash the process. Keep the data dirty so the
      // next mutation retries the flush.
      try {
        this.flush()
      } catch (err) {
        this.dirty = true
        console.error(`[store] flush failed for ${this.file}:`, err)
      }
    }, FLUSH_DELAY_MS)
    // Don't keep the event loop alive just for a pending flush.
    this.timer.unref?.()
  }

  flush() {
    if (!this.dirty) return
    this.dirty = false
    const tmp = `${this.file}.tmp`
    fs.mkdirSync(path.dirname(this.file), { recursive: true })
    fs.writeFileSync(tmp, JSON.stringify(this.all(), null, 1))
    fs.renameSync(tmp, this.file)
  }
}

export class Store {
  private collections = new Map<string, Collection<Doc>>()

  constructor(private dir: string) {
    fs.mkdirSync(dir, { recursive: true })
  }

  collection<T extends Doc>(name: string): Collection<T> {
    let col = this.collections.get(name)
    if (!col) {
      col = new Collection<Doc>(path.join(this.dir, `${name}.json`))
      this.collections.set(name, col)
    }
    return col as unknown as Collection<T>
  }

  flushAll() {
    for (const col of this.collections.values()) col.flush()
  }
}
