import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Cpu, HardDrive, MemoryStick, Server as ServerIcon, ArrowRight, Activity, Boxes, Container, LibraryBig, Plus, Rocket } from 'lucide-react'
import { api } from '../api/client.ts'
import { wsClient } from '../api/ws.ts'
import type { AuditEntry, HostSnapshot, NodeInfo, ServerSummary, SystemInfo } from '../api/types.ts'
import { useServerList } from '../state/useServers.ts'
import { useAuth } from '../state/AuthContext.tsx'
import { useT } from '../i18n/index.tsx'
import { Badge, Button, Card, CardHeader, Skeleton } from '../components/ui.tsx'
import { Sparkline, ProgressBar } from '../components/Sparkline.tsx'
import { StatusPill } from '../components/StatusPill.tsx'
import { GameIcon } from '../components/GameIcon.tsx'
import { formatBytes, formatUptime, timeAgo } from '../lib/format.ts'
import { auditActionLabel, auditActionTint } from '../lib/audit.ts'

function MetricCard({
  icon,
  label,
  value,
  sub,
  pct,
  history,
}: {
  icon: React.ReactNode
  label: string
  value: string
  sub?: string
  pct?: number
  history?: number[]
}) {
  return (
    <Card className="card-hover fade-in-up p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="microlabel flex items-center gap-2 whitespace-nowrap">
            <span className="sheen inline-flex h-7 w-7 items-center justify-center rounded-lg bg-accent/15 text-accent">{icon}</span>
            {label}
          </div>
          <div className="tabular mt-2.5 truncate font-display text-2xl font-bold tracking-tight">{value}</div>
          {sub && <div className="tabular mt-0.5 truncate text-xs text-muted">{sub}</div>}
        </div>
        {history && history.length > 1 && <Sparkline values={history} max={100} className="mt-1 shrink-0 text-accent" />}
      </div>
      {/* Low percentages stay a capped rounded sliver (not a dot): the fill keeps a min-width wider than its height. */}
      {pct !== undefined && <ProgressBar pct={pct} className="mt-3 [&>div]:min-w-3" />}
    </Card>
  )
}

/** One machine in the compact hosts strip (only rendered when nodes exist). */
function MachineChip({
  name,
  online,
  local,
  cpuPct,
  memUsed,
  memTotal,
  diskFree,
  errorTooltip,
}: {
  name: string
  online: boolean
  local?: boolean
  cpuPct: number | null
  memUsed: number | null
  memTotal: number | null
  diskFree: number | null
  errorTooltip?: string | null
}) {
  const t = useT()
  return (
    <div className="glass-subtle fade-in-up flex items-center gap-2.5 rounded-xl px-3.5 py-2.5" title={errorTooltip ?? undefined}>
      <span
        aria-hidden
        className={`h-2 w-2 shrink-0 rounded-full ${online ? 'bg-success glow-success' : 'bg-danger'}`}
      />
      <span className="flex min-w-0 flex-1 items-center gap-1.5">
        <Boxes size={13} className="shrink-0 text-muted/70" />
        <span className="truncate text-[0.8125rem] font-semibold">{name}</span>
        {local && <Badge className="shrink-0 border-accent/30 bg-accent/10 text-accent">{t('nodes.localBadge')}</Badge>}
      </span>
      {online ? (
        <span className="tabular flex shrink-0 items-center gap-2.5 text-[0.6875rem] text-muted">
          <span>{cpuPct != null ? `${cpuPct.toFixed(0)}% CPU` : '—'}</span>
          <span className="max-sm:hidden">{memUsed != null && memTotal != null ? `${formatBytes(memUsed)} / ${formatBytes(memTotal)}` : '—'}</span>
          <span className="max-md:hidden">{diskFree != null ? t('dash.diskFree', { free: formatBytes(diskFree) }) : '—'}</span>
        </span>
      ) : (
        <span className="shrink-0 text-[0.6875rem] font-medium text-danger">{t('nodes.offline')}</span>
      )}
    </div>
  )
}

function HeroStat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="min-w-0">
      <div className="microlabel">{label}</div>
      <div className="tabular mt-0.5 truncate font-display text-xl font-bold tracking-tight">
        {value}
        {sub && <span className="ml-1.5 text-sm font-medium text-muted">{sub}</span>}
      </div>
    </div>
  )
}

function ServerCard({ server }: { server: ServerSummary }) {
  const t = useT()
  const players = server.query?.online ? `${server.query.playersOnline ?? 0}/${server.query.playersMax ?? '?'}` : null
  const gamePort = server.ports[0]
  return (
    <Link
      to={`/servers/${server.id}`}
      className="glass-subtle card-hover group flex items-center gap-3 rounded-xl p-3.5 hover:bg-elevated/50"
    >
      <GameIcon icon={server.icon} color={server.color} boxed size={20} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate font-semibold">{server.name}</span>
          {server.runtime === 'docker' && <Container size={13} className="shrink-0 text-accent2" aria-label="Docker" />}
          {players && <Badge className="tabular">{players} {t('servers.players')}</Badge>}
        </div>
        <div className="mt-0.5 flex items-center gap-2 text-xs text-muted">
          <span className="truncate">{server.blueprintName}</span>
          {server.nodeId && (
            <Badge className="shrink-0" title={t('servers.nodeBadge', { name: server.nodeName ?? '' })}>
              <Boxes size={10} />
              {server.nodeName}
            </Badge>
          )}
          {gamePort && (
            <>
              <span>·</span>
              <span className="tabular font-mono">:{gamePort.port}</span>
            </>
          )}
          {server.status === 'running' && server.resources && (
            <>
              <span>·</span>
              <span className="tabular">{server.resources.cpuPct.toFixed(0)}% CPU</span>
              <span>·</span>
              <span className="tabular">{formatBytes(server.resources.memBytes)}</span>
              <span className="max-sm:hidden">·</span>
              <span className="tabular max-sm:hidden">{formatUptime(server.uptimeS)}</span>
            </>
          )}
        </div>
      </div>
      <StatusPill status={server.status} size="sm" />
      <ArrowRight size={15} className="text-muted/40 transition-transform group-hover:translate-x-0.5 group-hover:text-accent" />
    </Link>
  )
}

/**
 * Content-shaped loading state: mirrors the real dashboard layout (hero band,
 * 4 metric cards, server-list + activity cards) block for block so the swap
 * to live content doesn't jump.
 */
function DashboardSkeleton() {
  return (
    <div className="fade-in-up" aria-busy="true">
      <Card className="mb-6 p-5 sm:p-6">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div className="min-w-0">
            <Skeleton className="h-10 w-64 max-w-full" />
            <Skeleton className="mt-2 h-4 w-44 rounded-full" />
          </div>
          <Skeleton className="h-9 w-32" />
        </div>
        <div className="mt-5 grid grid-cols-2 gap-x-6 gap-y-4 border-t border-line/50 pt-4 sm:flex sm:flex-wrap sm:gap-x-10">
          {[0, 1, 2, 3].map((i) => (
            <div key={i}>
              <Skeleton className="h-3 w-16 rounded-full" />
              <Skeleton className="mt-1.5 h-7 w-20" />
            </div>
          ))}
        </div>
      </Card>
      <div className="stagger mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <Card key={i} className="fade-in-up p-4">
            <div className="flex h-7 items-center gap-2">
              <Skeleton className="h-7 w-7 rounded-lg" />
              <Skeleton className="h-3 w-20 rounded-full" />
            </div>
            <Skeleton className="mt-2.5 h-8 w-24" />
            <Skeleton className="mt-0.5 h-4 w-16 rounded-full" />
            <Skeleton className="mt-3 h-2 w-full rounded-full" />
          </Card>
        ))}
      </div>
      <div className="grid gap-4 md:grid-cols-3">
        <Card className="md:col-span-2">
          <div className="border-b border-line/60 px-4 py-3">
            <Skeleton className="h-5 w-24 rounded-full" />
          </div>
          <div className="space-y-2 p-3">
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} className="h-16 w-full" />
            ))}
          </div>
        </Card>
        <Card className="self-start">
          <div className="border-b border-line/60 px-4 py-3">
            <Skeleton className="h-5 w-28 rounded-full" />
          </div>
          <div className="space-y-1 p-3">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-11 w-full" />
            ))}
          </div>
        </Card>
      </div>
    </div>
  )
}

/**
 * First-run welcome: with zero servers the dashboard must invite, not present
 * a dead cockpit — replaces the server-list card until the first server exists.
 */
function FirstRunPanel() {
  const t = useT()
  return (
    <Card className="fade-in-up relative overflow-hidden p-6 sm:p-8">
      <div
        aria-hidden
        className="pointer-events-none absolute -right-16 -top-20 h-48 w-64 rounded-full bg-[radial-gradient(closest-side,color-mix(in_oklab,var(--t-accent)_16%,transparent),transparent)]"
      />
      <div className="relative">
        <div className="glass-subtle inline-flex rounded-2xl p-3.5 text-accent">
          <Rocket size={26} />
        </div>
        <h2 className="mt-4 font-display text-xl font-bold tracking-tight">{t('firstrun.title')}</h2>
        <p className="mt-1.5 max-w-md text-sm leading-relaxed text-muted">{t('firstrun.body')}</p>
        <div className="mt-5 flex flex-wrap items-center gap-2">
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
      </div>
    </Card>
  )
}

function greetingKey(): 'dash.greetingMorning' | 'dash.greetingAfternoon' | 'dash.greetingEvening' | 'dash.greetingNight' {
  const h = new Date().getHours()
  if (h < 5) return 'dash.greetingNight'
  if (h < 12) return 'dash.greetingMorning'
  if (h < 18) return 'dash.greetingAfternoon'
  return 'dash.greetingEvening'
}

export function Dashboard() {
  const t = useT()
  const { user } = useAuth()
  const { servers } = useServerList()
  const [system, setSystem] = useState<SystemInfo | null>(null)
  const [history, setHistory] = useState<HostSnapshot[]>([])
  const [audit, setAudit] = useState<AuditEntry[] | null>(null)
  const [nodes, setNodes] = useState<NodeInfo[] | null>(null)

  // Hosts strip: nodes are admin-scoped; non-admins never fetch and never
  // see the strip (same as zero nodes).
  useEffect(() => {
    if (user?.role !== 'admin') return
    const loadNodes = () => void api.get<{ nodes: NodeInfo[] }>('/api/nodes').then((r) => setNodes(r.nodes)).catch(() => undefined)
    loadNodes()
    const timer = setInterval(loadNodes, 10_000)
    return () => clearInterval(timer)
  }, [user])

  useEffect(() => {
    void api.get<{ system: SystemInfo }>('/api/system').then((r) => setSystem(r.system)).catch(() => undefined)
    void api
      .get<{ history: HostSnapshot[] }>('/api/system/metrics?limit=120')
      .then((r) =>
        setHistory((live) => {
          // Merge instead of replace: live WS samples may already have arrived
          // while the fetch was in flight — keep them, drop the overlap.
          const firstLiveTs = live[0]?.ts ?? Infinity
          return [...r.history.filter((h) => h.ts < firstLiveTs), ...live]
        }),
      )
      .catch(() => undefined)
    const admin = user?.role === 'admin'
    if (admin) {
      void api.get<{ entries: AuditEntry[] }>('/api/audit?limit=8').then((r) => setAudit(r.entries)).catch(() => undefined)
      wsClient.subscribe('audit')
    }
    const off = wsClient.onMessage((msg) => {
      if (msg.t === 'metrics') {
        const snap = msg.snap as HostSnapshot
        setHistory((prev) => [...prev.slice(-719), snap])
      } else if (msg.t === 'audit' && admin) {
        // Live feed: prepend new entries so "Recent activity" stays current.
        const entry = msg.entry as AuditEntry
        setAudit((prev) => [entry, ...(prev ?? [])].slice(0, 8))
      }
    })
    return () => {
      off()
      if (admin) wsClient.unsubscribe('audit')
    }
  }, [user])

  const latest = history[history.length - 1] ?? system?.metrics ?? null
  const cpuHistory = useMemo(() => history.slice(-60).map((h) => h.cpuPct), [history])
  const memHistory = useMemo(() => history.slice(-60).map((h) => (h.memUsedBytes / Math.max(1, h.memTotalBytes)) * 100), [history])
  const diskHistory = useMemo(
    () => history.slice(-60).map((h) => (h.diskUsedBytes / Math.max(1, h.diskTotalBytes)) * 100),
    [history],
  )
  const running = servers?.filter((s) => s.status === 'running' || s.status === 'starting').length ?? 0
  const playersTotal = servers?.reduce((sum, s) => sum + (s.query?.online ? s.query.playersOnline ?? 0 : 0), 0) ?? 0
  // Per-status breakdown for the 4th metric card (grouping mirrors the Servers page filters).
  const statusBreakdown = useMemo(() => {
    const count = (statuses: string[]) => servers?.filter((s) => statuses.includes(s.status)).length ?? 0
    return [
      { key: 'status.running' as const, dot: 'bg-success', n: count(['running', 'starting']) },
      { key: 'status.offline' as const, dot: 'bg-muted/60', n: count(['offline', 'stopping', 'node-offline']) },
      { key: 'status.installing' as const, dot: 'bg-accent', n: count(['installing', 'updating']) },
      { key: 'status.crashed' as const, dot: 'bg-danger', n: count(['crashed', 'install_failed']) },
    ]
  }, [servers])

  // Initial load: a content-shaped skeleton instead of a blank cockpit full of
  // em dashes (the server list is the last gate — metrics stream in live).
  if (!servers) return <DashboardSkeleton />

  return (
    <div className="fade-in-up">
      {/* Hero: glassy welcome panel — greeting, live summary, quick stats */}
      <Card className="relative mb-6 overflow-hidden p-5 sm:p-6">
        <div
          aria-hidden
          className="pointer-events-none absolute -right-20 -top-24 h-56 w-72 rounded-full bg-[radial-gradient(closest-side,color-mix(in_oklab,var(--t-accent)_18%,transparent),transparent)]"
        />
        <div
          aria-hidden
          className="pointer-events-none absolute -bottom-24 -left-16 h-48 w-64 rounded-full bg-[radial-gradient(closest-side,color-mix(in_oklab,var(--t-accent2)_14%,transparent),transparent)]"
        />
        <div className="relative flex flex-wrap items-end justify-between gap-4">
          <div className="min-w-0">
            <h1 className="font-display text-[1.625rem] font-bold tracking-tight">
              <span className="text-gradient">{t(greetingKey(), { name: user?.username ?? '' })}</span>
            </h1>
            <p className="mt-1 text-sm text-muted">{t('dash.subtitle')}</p>
          </div>
          <Link to="/servers/new">
            <Button variant="primary">
              <Plus size={15} />
              {t('dash.newServer')}
            </Button>
          </Link>
        </div>
        <div className="relative mt-5 grid grid-cols-2 gap-x-6 gap-y-4 border-t border-line/50 pt-4 sm:flex sm:flex-wrap sm:gap-x-10">
          <HeroStat label={t('dash.servers')} value={`${running}/${servers.length}`} sub={t('dash.running')} />
          <HeroStat label={t('dash.players')} value={String(playersTotal)} />
          <HeroStat label={t('dash.panelUptime')} value={system ? formatUptime(system.panelUptimeS) : '—'} />
          <HeroStat label={t('dash.load')} value={latest?.load1 != null ? latest.load1.toFixed(2) : '—'} />
        </div>
      </Card>

      {/* Hosts strip (AMP-overview style): only when remote nodes exist —
          single-machine panels keep exactly yesterday's dashboard. */}
      {nodes && nodes.length > 0 && (
        <div className="stagger mb-6 grid gap-4 lg:grid-cols-2">
          <MachineChip
            name={t('nodes.thisPanel')}
            online
            local
            cpuPct={latest?.cpuPct ?? null}
            memUsed={latest?.memUsedBytes ?? null}
            memTotal={latest?.memTotalBytes ?? null}
            diskFree={latest && latest.diskTotalBytes > 0 ? latest.diskTotalBytes - latest.diskUsedBytes : null}
          />
          {nodes.map((n) => (
            <MachineChip
              key={n.id}
              name={n.name}
              online={n.health.online}
              cpuPct={n.health.cpuPct}
              memUsed={n.health.memUsedBytes}
              memTotal={n.health.memTotalBytes}
              diskFree={
                n.health.diskTotalBytes != null && n.health.diskUsedBytes != null && n.health.diskTotalBytes > 0
                  ? n.health.diskTotalBytes - n.health.diskUsedBytes
                  : null
              }
              errorTooltip={n.health.error}
            />
          ))}
        </div>
      )}

      <div className="stagger mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          icon={<Cpu size={13} />}
          label={t('dash.cpu')}
          value={latest ? `${latest.cpuPct.toFixed(1)}%` : '—'}
          sub={system ? `${system.cpus}× ${system.cpuModel.slice(0, 28)}` : undefined}
          pct={latest?.cpuPct}
          history={cpuHistory}
        />
        <MetricCard
          icon={<MemoryStick size={13} />}
          label={t('dash.memory')}
          value={latest ? formatBytes(latest.memUsedBytes) : '—'}
          sub={latest ? `/ ${formatBytes(latest.memTotalBytes)}` : undefined}
          pct={latest ? (latest.memUsedBytes / Math.max(1, latest.memTotalBytes)) * 100 : undefined}
          history={memHistory}
        />
        <MetricCard
          icon={<HardDrive size={13} />}
          label={t('dash.disk')}
          value={latest && latest.diskTotalBytes > 0 ? formatBytes(latest.diskUsedBytes) : '—'}
          sub={latest && latest.diskTotalBytes > 0 ? `/ ${formatBytes(latest.diskTotalBytes)}` : undefined}
          pct={latest && latest.diskTotalBytes > 0 ? (latest.diskUsedBytes / latest.diskTotalBytes) * 100 : undefined}
          history={diskHistory}
        />
        {/* 4th card: per-status fleet breakdown (the totals already live in the hero band). */}
        <Card className="card-hover fade-in-up p-4">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="microlabel flex items-center gap-2 whitespace-nowrap">
                <span className="sheen inline-flex h-7 w-7 items-center justify-center rounded-lg bg-accent/15 text-accent">
                  <ServerIcon size={13} />
                </span>
                {t('dash.servers')}
              </div>
              <div className="tabular mt-2.5 truncate font-display text-2xl font-bold tracking-tight">{servers.length}</div>
            </div>
          </div>
          <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
            {statusBreakdown
              .filter((s, i) => i < 2 || s.n > 0)
              .map((s) => (
                <span key={s.key} className="tabular inline-flex items-center gap-1.5">
                  <span aria-hidden className={`h-1.5 w-1.5 rounded-full ${s.dot}`} />
                  {s.n} {t(s.key)}
                </span>
              ))}
          </div>
        </Card>
      </div>

      {/* md, not lg: the 2:1 split already works at ~720px content width, and
          a full-width activity feed below the fold wastes a tablet screen. */}
      <div className="grid gap-4 md:grid-cols-3">
        <div className="md:col-span-2">
          {servers.length === 0 ? (
            <FirstRunPanel />
          ) : (
            <Card className="fade-in-up">
              <CardHeader
                title={t('nav.servers')}
                actions={
                  <Link
                    to="/servers"
                    className="rounded-lg px-1.5 py-1 text-xs font-medium text-accent hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
                  >
                    {t('dash.viewAll')} →
                  </Link>
                }
              />
              <div className="stagger space-y-2 p-3">
                {servers.slice(0, 6).map((s) => <ServerCard key={s.id} server={s} />)}
              </div>
            </Card>
          )}
        </div>

        <Card className="fade-in-up self-start">
          <CardHeader title={t('dash.recentActivity')} />
          <div className="p-3">
            {audit === null && user?.role === 'admin' && (
              <div className="space-y-1" aria-busy="true">
                {[0, 1, 2].map((i) => (
                  <Skeleton key={i} className="h-11 w-full" />
                ))}
              </div>
            )}
            {user?.role !== 'admin' && <p className="px-2 py-6 text-center text-sm text-muted">—</p>}
            {audit && audit.length === 0 && <p className="px-2 py-6 text-center text-sm text-muted">{t('activity.empty')}</p>}
            <div className="space-y-1">
              {audit?.map((entry) => (
                <div key={entry.id} className="flex items-start gap-2 rounded-lg px-2 py-1.5 transition-colors hover:bg-elevated/70">
                  <span className="sheen mt-0.5 inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-lg bg-accent/12 text-accent/80">
                    <Activity size={11} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-x-1.5 gap-y-0.5 text-[0.8125rem]">
                      <span className="font-semibold">{entry.username}</span>
                      <Badge title={entry.action} className={`max-w-full font-mono ${auditActionTint(entry.action)}`}>
                        {auditActionLabel(entry.action, t)}
                      </Badge>
                      {entry.target && <span className="min-w-0 truncate text-text/80">{entry.target}</span>}
                    </div>
                    <div className="text-[0.6875rem] text-muted/70">{timeAgo(entry.ts, t)}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </Card>
      </div>
    </div>
  )
}
