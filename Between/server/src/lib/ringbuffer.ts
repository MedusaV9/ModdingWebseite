/**
 * Fixed-capacity ring buffer: O(1) push with no shifting/splicing once full.
 * Backs the in-memory metrics history (host + per-server samples) — anything
 * that must keep "the last N" without unbounded growth. Zero dependencies.
 */
export class RingBuffer<T> {
  private items: T[] = []
  private start = 0

  constructor(readonly cap: number) {
    if (!Number.isInteger(cap) || cap <= 0) throw new Error('RingBuffer capacity must be a positive integer')
  }

  get length(): number {
    return this.items.length
  }

  /** Newest item, or undefined while empty. */
  get last(): T | undefined {
    if (this.items.length === 0) return undefined
    return this.items[(this.start + this.items.length - 1) % this.cap]
  }

  push(item: T): void {
    if (this.items.length < this.cap) {
      this.items.push(item)
    } else {
      this.items[this.start] = item
      this.start = (this.start + 1) % this.cap
    }
  }

  /** Copy in oldest→newest order; with lastN, only the newest N items. */
  toArray(lastN = this.items.length): T[] {
    const n = Math.max(0, Math.min(Math.trunc(lastN), this.items.length))
    const out: T[] = new Array(n)
    for (let i = 0; i < n; i++) {
      out[i] = this.items[(this.start + this.items.length - n + i) % this.cap]
    }
    return out
  }

  clear(): void {
    this.items = []
    this.start = 0
  }
}
