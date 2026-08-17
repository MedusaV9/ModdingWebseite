import type { Store, Collection } from '../lib/jsonstore.ts'
import type { AuditEntry } from '../types.ts'
import type { AuthedRequest } from '../auth/service.ts'
import { nowIso } from '../lib/util.ts'

const MAX_ENTRIES = 10_000

export class AuditService {
  readonly entries: Collection<AuditEntry>
  /** Called with each freshly written entry (drives the live dashboard feed). */
  onEntry: ((entry: AuditEntry) => void) | null = null

  constructor(store: Store) {
    this.entries = store.collection<AuditEntry>('audit')
  }

  log(req: AuthedRequest | null, action: string, opts: { target?: string; serverId?: string; meta?: Record<string, unknown> } = {}) {
    const entry = this.entries.insert({
      ts: nowIso(),
      userId: req?.user?.id ?? null,
      username: req?.user?.username ?? 'system',
      ip: req?.ip,
      action,
      target: opts.target,
      serverId: opts.serverId ?? null,
      meta: opts.meta,
    })
    if (this.entries.size() > MAX_ENTRIES) {
      const sorted = this.entries.all().sort((a, b) => a.ts.localeCompare(b.ts))
      for (const old of sorted.slice(0, this.entries.size() - MAX_ENTRIES)) this.entries.remove(old.id)
    }
    this.onEntry?.(entry)
  }

  list(filter: { serverId?: string; userId?: string; action?: string; limit?: number; offset?: number }): {
    entries: AuditEntry[]
    total: number
  } {
    let all = this.entries.all().sort((a, b) => b.ts.localeCompare(a.ts))
    if (filter.serverId) all = all.filter((e) => e.serverId === filter.serverId)
    if (filter.userId) all = all.filter((e) => e.userId === filter.userId)
    if (filter.action) all = all.filter((e) => e.action.startsWith(filter.action!))
    const total = all.length
    const offset = Math.max(0, filter.offset ?? 0)
    const limit = Math.min(200, Math.max(1, filter.limit ?? 50))
    return { entries: all.slice(offset, offset + limit), total }
  }
}
