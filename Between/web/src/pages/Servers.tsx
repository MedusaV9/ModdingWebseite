import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowDownUp, Boxes, Container, LibraryBig, Plus, Rocket, Search, Server as ServerIcon } from 'lucide-react'
import type { ServerStatus, ServerSummary } from '../api/types.ts'
import { useServerList } from '../state/useServers.ts'
import { useT } from '../i18n/index.tsx'
import { Badge, Button, Chip, EmptyState, Input, PageHeader, SegmentedControl, Skeleton } from '../components/ui.tsx'
import { StatusPill } from '../components/StatusPill.tsx'
import { GameIcon } from '../components/GameIcon.tsx'
import { formatBytes, formatUptime } from '../lib/format.ts'

const FILTERS: (ServerStatus | 'all')[] = ['all', 'running', 'offline', 'crashed', 'installing']

type ServersSort = 'status' | 'name' | 'players'
const SORTS: ServersSort[] = ['status', 'name', 'players']
const SORT_STORAGE_KEY = 'between.serversSort'

// Status sort: alive first, then anything in motion (worth watching), then
// failed states (need attention before the merely idle), offline last.
const STATUS_RANK: Record<ServerStatus, number> = {
  running: 0,
  starting: 1,
  stopping: 2,
  installing: 3,
  updating: 4,
  crashed: 5,
  install_failed: 6,
  'node-offline': 7,
  offline: 8,
}

const byName = (a: ServerSummary, b: ServerSummary) =>
  a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true })

// -1 for servers without a live query so a reported "0 players" still ranks
// above "unknown"; ties fall back to name for a stable, predictable order.
const playerCount = (s: ServerSummary) => (s.query?.online ? (s.query.playersOnline ?? 0) : -1)

const COMPARATORS: Record<ServersSort, (a: ServerSummary, b: ServerSummary) => number> = {
  name: byName,
  status: (a, b) => STATUS_RANK[a.status] - STATUS_RANK[b.status] || byName(a, b),
  players: (a, b) => playerCount(b) - playerCount(a) || byName(a, b),
}

/** Content-shaped loading card mirroring the real server card's layout. */
function ServerCardSkeleton() {
  return (
    <div className="glass-subtle fade-in-up rounded-2xl p-4" aria-busy="true">
      <div className="flex items-center gap-3">
        <Skeleton className="h-9 w-9" />
        <div className="min-w-0 flex-1">
          <Skeleton className="h-5.5 w-40 max-w-full rounded-full" />
          <Skeleton className="mt-1.5 h-3.5 w-24 rounded-full" />
        </div>
        <Skeleton className="h-7 w-20 rounded-full" />
      </div>
      <div className="mt-3 grid grid-cols-2 gap-x-2 gap-y-2.5 border-t border-line/60 pt-3 sm:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="flex flex-col items-center">
            <Skeleton className="h-3.5 w-10 rounded-full" />
            <Skeleton className="mt-1.5 h-4 w-12 rounded-full" />
          </div>
        ))}
      </div>
    </div>
  )
}

export function Servers() {
  const t = useT()
  const { servers } = useServerList()
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState<ServerStatus | 'all'>('all')
  // Read once on mount (same pattern as `between.lang`); persisted on change.
  const [sort, setSort] = useState<ServersSort>(() => {
    const saved = localStorage.getItem(SORT_STORAGE_KEY)
    return SORTS.includes(saved as ServersSort) ? (saved as ServersSort) : 'status'
  })

  const changeSort = (next: ServersSort) => {
    localStorage.setItem(SORT_STORAGE_KEY, next)
    setSort(next)
  }

  // Filter first, then sort. filter() yields a fresh array, so the in-place
  // sort never mutates the shared server list from the store.
  const filtered = useMemo(() => {
    if (!servers) return null
    const q = query.trim().toLowerCase()
    return servers
      .filter((s) => {
        if (filter !== 'all') {
          if (filter === 'running' && !['running', 'starting'].includes(s.status)) return false
          if (filter === 'offline' && !['offline', 'node-offline'].includes(s.status)) return false
          if (filter === 'crashed' && !['crashed', 'install_failed'].includes(s.status)) return false
          if (filter === 'installing' && !['installing', 'updating'].includes(s.status)) return false
        }
        if (!q) return true
        return (
          s.name.toLowerCase().includes(q) ||
          s.blueprintName.toLowerCase().includes(q) ||
          s.tags.some((tag) => tag.toLowerCase().includes(q))
        )
      })
      .sort(COMPARATORS[sort])
  }, [servers, query, filter, sort])

  return (
    <div className="fade-in-up">
      <PageHeader
        title={t('servers.title')}
        subtitle={t('servers.subtitle')}
        actions={
          <Link to="/servers/new">
            <Button variant="primary">
              <Plus size={15} />
              {t('servers.create')}
            </Button>
          </Link>
        }
      />

      <div className="mb-6 flex flex-wrap items-center gap-2">
        <div className="relative w-full max-w-xs">
          <Search size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t('servers.searchPlaceholder')} className="rounded-full pl-8" />
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          {FILTERS.map((f) => (
            <Chip key={f} active={filter === f} onClick={() => setFilter(f)}>
              {f === 'all' ? t('servers.filter.all') : t(`status.${f}` as 'status.offline')}
            </Chip>
          ))}
        </div>
        {/* Sort control: the accessible name lives on the radiogroup itself;
            the icon is the purely visual "sort" cue. */}
        <div className="flex items-center gap-1.5 sm:ml-auto">
          <ArrowDownUp size={13} className="shrink-0 text-muted" aria-hidden />
          <SegmentedControl
            size="sm"
            aria-label={t('servers.sortLabel')}
            options={[
              { value: 'status', label: t('servers.sort.status') },
              { value: 'name', label: t('servers.sort.name') },
              { value: 'players', label: t('servers.sort.players') },
            ]}
            value={sort}
            onChange={changeSort}
          />
        </div>
      </div>

      {!filtered && (
        <div className="stagger grid gap-4 md:grid-cols-2">
          <ServerCardSkeleton />
          <ServerCardSkeleton />
        </div>
      )}
      {/* Two distinct zero states: filters hiding existing servers keep the
          plain "no results" line; a genuinely empty node gets the first-run
          invitation (same treatment as the dashboard welcome panel). */}
      {filtered && filtered.length === 0 && servers && servers.length > 0 && (
        <EmptyState icon={<ServerIcon size={40} />} title={t('servers.noneMatching')} />
      )}
      {filtered && filtered.length === 0 && servers && servers.length === 0 && (
        <EmptyState
          icon={<Rocket size={40} />}
          title={t('firstrun.title')}
          body={t('firstrun.body')}
          action={
            <div className="flex flex-wrap items-center justify-center gap-2">
              <Link to="/servers/new">
                <Button variant="primary">
                  <Plus size={15} />
                  {t('dash.createFirst')}
                </Button>
              </Link>
              <Link to="/catalog">
                <Button variant="secondary">
                  <LibraryBig size={14} />
                  {t('firstrun.browse')}
                </Button>
              </Link>
            </div>
          }
        />
      )}

      <div className="stagger grid gap-4 md:grid-cols-2">
        {filtered?.map((server) => (
          <Link
            key={server.id}
            to={`/servers/${server.id}`}
            // Blur-free glass tint: one backdrop-filter per card would blow the
            // perf budget on nodes with many servers (same call as the
            // blueprint/catalog grids and the dashboard server rows).
            className="glass-subtle card-hover fade-in-up group rounded-2xl p-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
          >
            <div className="flex items-center gap-3">
              <GameIcon icon={server.icon} color={server.color} boxed size={22} />
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="truncate font-display text-[0.9375rem] font-semibold tracking-tight">{server.name}</span>
                  {server.tags.slice(0, 3).map((tag) => (
                    <Badge key={tag} className="max-sm:hidden">{tag}</Badge>
                  ))}
                </div>
                <div className="mt-0.5 flex items-center gap-1.5 truncate text-xs text-muted">
                  <span className="truncate">{server.blueprintName}</span>
                  {server.runtime === 'docker' && <Container size={12} className="shrink-0 text-accent2" aria-label="Docker" />}
                  {server.nodeId && (
                    <Badge className="shrink-0" title={t('servers.nodeBadge', { name: server.nodeName ?? '' })}>
                      <Boxes size={10} />
                      {server.nodeName}
                    </Badge>
                  )}
                </div>
              </div>
              <StatusPill status={server.status} />
            </div>
            <div className="mt-3 grid grid-cols-2 gap-x-2 gap-y-2.5 border-t border-line/60 pt-3 text-center sm:grid-cols-4">
              <div>
                <div className="microlabel">CPU</div>
                <div className="tabular mt-0.5 text-[0.8125rem] font-semibold">
                  {server.status === 'running' && server.resources ? `${server.resources.cpuPct.toFixed(0)}%` : '—'}
                </div>
              </div>
              <div>
                <div className="microlabel">RAM</div>
                <div className="tabular mt-0.5 text-[0.8125rem] font-semibold">
                  {server.status === 'running' && server.resources ? formatBytes(server.resources.memBytes) : '—'}
                </div>
              </div>
              <div>
                <div className="microlabel">{t('servers.uptime')}</div>
                <div className="tabular mt-0.5 text-[0.8125rem] font-semibold">{server.status === 'running' ? formatUptime(server.uptimeS) : '—'}</div>
              </div>
              <div>
                <div className="microlabel">{t('dash.players')}</div>
                <div className="tabular mt-0.5 text-[0.8125rem] font-semibold">
                  {server.query?.online ? `${server.query.playersOnline ?? 0}/${server.query.playersMax ?? '?'}` : '—'}
                </div>
              </div>
            </div>
          </Link>
        ))}
      </div>
    </div>
  )
}
