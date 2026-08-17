import { useDeferredValue, useEffect, useMemo, useRef, useState, type FormEvent, type KeyboardEvent } from 'react'
import { createPortal } from 'react-dom'
import { ChevronRight, Clock, Download, Medal, MoreVertical, Search, SendHorizonal, Users, X } from 'lucide-react'
import { useServer } from './ServerDetail.tsx'
import { useT } from '../../i18n/index.tsx'
import { useToast } from '../../state/ToastContext.tsx'
import { api, ApiError } from '../../api/client.ts'
import { wsClient } from '../../api/ws.ts'
import type { Blueprint, ConsoleLine, HostSnapshot, QueryResult, ResourceSnapshot } from '../../api/types.ts'
import { Badge, Button, Card, IconButton, Input, cx } from '../../components/ui.tsx'
import { ConfirmModal } from '../../components/Modal.tsx'
import { Terminal } from '../../components/Terminal.tsx'
import { Sparkline } from '../../components/Sparkline.tsx'
import { formatBytes, formatDuration, formatUptime } from '../../lib/format.ts'

const PLAYERS_SHOWN = 20
const SPARK_SAMPLES = 60
const ACTIVE_STATUSES = ['running', 'starting', 'stopping']
const TIMESTAMPS_KEY = 'between.consoleTimestamps'

// Compact below sm: the strip renders as one row of four narrow cells there
// (see the grid), so paddings/type shrink and the sparkline steps aside.
function StatBox({ label, value, spark, sparkMax }: { label: string; value: string; spark?: number[]; sparkMax?: number }) {
  return (
    <div className="glass-subtle fade-in-up flex items-center justify-between gap-2 rounded-xl px-2.5 py-2 sm:px-3.5 sm:py-2.5">
      <div className="min-w-0">
        <div className="microlabel truncate">{label}</div>
        <div className="tabular mt-0.5 truncate font-mono text-[0.8125rem] font-semibold sm:text-[0.9375rem]">{value}</div>
      </div>
      {spark && spark.length > 1 && (
        <Sparkline values={spark} max={sparkMax} width={72} height={26} className="shrink-0 text-accent max-sm:hidden" />
      )}
    </div>
  )
}

type PlayerAction = NonNullable<Blueprint['playerActions']>[number]

function PlayerActionsMenu({ actions, onPick }: { actions: PlayerAction[]; onPick: (action: PlayerAction) => void }) {
  const t = useT()
  const btnRef = useRef<HTMLButtonElement>(null)
  const [pos, setPos] = useState<{ top: number; right: number } | null>(null)

  const toggle = () => {
    if (pos) return setPos(null)
    const r = btnRef.current?.getBoundingClientRect()
    if (!r) return
    // Portal with fixed positioning: the players list is a clipping scroll
    // container, so an in-flow absolute menu would be cut off at the edges.
    const estimatedH = actions.length * 28 + 10
    const openUp = r.bottom + 4 + estimatedH > window.innerHeight - 8
    setPos({ top: openUp ? r.top - estimatedH - 4 : r.bottom + 4, right: window.innerWidth - r.right })
  }

  return (
    <>
      <button
        ref={btnRef}
        type="button"
        onClick={toggle}
        aria-haspopup="menu"
        aria-expanded={pos !== null}
        aria-label={t('common.actions')}
        title={t('common.actions')}
        className="pressable shrink-0 rounded-lg p-1 text-muted/70 hover:bg-elevated/70 hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
      >
        <MoreVertical size={13} />
      </button>
      {pos &&
        createPortal(
          <>
            <div className="fixed inset-0 z-40" onClick={() => setPos(null)} />
            <div
              role="menu"
              className="glass-strong scale-in fixed z-50 min-w-28 rounded-xl py-1"
              style={{ top: pos.top, right: pos.right }}
            >
              {actions.map((a) => (
                <button
                  key={a.key}
                  type="button"
                  role="menuitem"
                  onClick={() => {
                    setPos(null)
                    onPick(a)
                  }}
                  className="block w-full px-3 py-1.5 text-left text-xs text-text/90 hover:bg-elevated/70"
                >
                  {a.label}
                </button>
              ))}
            </div>
          </>,
          document.body,
        )}
    </>
  )
}

function PlayersCard({ players }: { players: NonNullable<QueryResult['players']> }) {
  const { server, sendCommand, can } = useServer()
  const t = useT()
  const toast = useToast()
  const [pending, setPending] = useState<{ action: PlayerAction; player: string } | null>(null)
  const [busy, setBusy] = useState(false)
  const shown = players.slice(0, PLAYERS_SHOWN)

  const actions = server.blueprint?.playerActions ?? []
  const showActions = server.status === 'running' && actions.length > 0 && can('server.command')

  const runAction = async (action: PlayerAction, player: string) => {
    // Names with spaces must reach the game console as one argument.
    const target = player.includes(' ') ? '"' + player + '"' : player
    try {
      await sendCommand(action.command.replaceAll('{{PLAYER}}', target))
      toast('success', t('players.actionSent', { action: action.label, player }))
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    }
  }

  const pick = (action: PlayerAction, player: string) => {
    if (action.confirm) setPending({ action, player })
    else void runAction(action, player)
  }

  return (
    <Card className="self-start overflow-hidden">
      <div className="flex items-center gap-2 border-b border-line/60 bg-elevated/40 px-3 py-2">
        <Users size={12} className="text-muted/70" />
        <span className="microlabel">{t('players.title')}</span>
        {players.length > 0 && <span className="tabular ml-auto font-mono text-[11px] text-muted/70">{players.length}</span>}
      </div>
      {players.length === 0 ? (
        <div className="px-3 py-2.5 text-xs text-muted/60">{t('players.none')}</div>
      ) : (
        <ul className="max-h-80 overflow-y-auto py-1">
          {shown.map((p, i) => (
            <li key={`${p.name}-${i}`} className="flex items-center gap-2 px-3 py-1.5 text-xs hover:bg-elevated/40">
              <span className="min-w-0 flex-1 truncate text-text/90">{p.name}</span>
              {p.score !== undefined && (
                <span className="inline-flex shrink-0 items-center gap-1 font-mono text-[11px] text-muted">
                  <Medal size={10} className="text-accent/70" />
                  {p.score}
                </span>
              )}
              {p.durationS !== undefined && <span className="shrink-0 font-mono text-[11px] text-muted/60">{formatDuration(p.durationS)}</span>}
              {showActions && <PlayerActionsMenu actions={actions} onPick={(a) => pick(a, p.name)} />}
            </li>
          ))}
          {players.length > PLAYERS_SHOWN && (
            <li className="px-3 py-1 text-[0.6875rem] text-muted/60">{t('players.more', { n: players.length - PLAYERS_SHOWN })}</li>
          )}
        </ul>
      )}
      {pending && (
        <ConfirmModal
          open
          onClose={() => setPending(null)}
          onConfirm={async () => {
            setBusy(true)
            await runAction(pending.action, pending.player)
            setBusy(false)
            setPending(null)
          }}
          message={t('players.actionConfirm', { action: pending.action.label, player: pending.player })}
          danger
          loading={busy}
        />
      )}
    </Card>
  )
}

function pad2(n: number): string {
  return String(n).padStart(2, '0')
}

function buildLogText(lines: ConsoleLine[]): string {
  return lines
    .map((l) => {
      const d = new Date(l.ts)
      return `[${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}] [${l.stream}] ${l.line}`
    })
    .join('\n')
}

export function ConsoleTab() {
  const { server, lines, sendCommand, can } = useServer()
  const t = useT()
  const toast = useToast()
  const [command, setCommand] = useState('')
  const [filter, setFilter] = useState('')
  // Timestamp gutter preference — default ON; only '0' means opted out.
  const [showTimestamps, setShowTimestamps] = useState(() => localStorage.getItem(TIMESTAMPS_KEY) !== '0')
  const searchRef = useRef<HTMLInputElement>(null)
  const history = useRef<string[]>([])
  const historyIdx = useRef(-1)
  const [sparkSamples, setSparkSamples] = useState<{ ts: number; cpu: number; mem: number }[]>([])
  const [hostMemTotal, setHostMemTotal] = useState<number | null>(null)
  // Always-current status for the seed effect below, which must not re-run
  // (and re-seed) on every status change.
  const statusRef = useRef(server.status)
  statusRef.current = server.status

  // Memory-sparkline scale fallback: without a configured limit the chart has
  // no reference max. The singleton WS client subscribes to the 'system'
  // channel by default, so host metric frames (5s cadence) already reach this
  // page — capture the static total once, no extra requests or subscriptions.
  useEffect(
    () =>
      wsClient.onMessage((msg) => {
        if (msg.t !== 'metrics') return
        const total = (msg.snap as HostSnapshot | undefined)?.memTotalBytes
        if (total) setHostMemTotal((prev) => prev ?? total)
      }),
    [],
  )

  // Seed once per server: pre-fill the sparklines from the backend's sample
  // ring so a reload doesn't start with empty charts. Live WS samples keep
  // appending afterwards; the ts filter drops the overlap at the boundary.
  useEffect(() => {
    if (!ACTIVE_STATUSES.includes(statusRef.current)) return
    let cancelled = false
    void api
      .get<{ history: ResourceSnapshot[] }>(`/api/servers/${server.id}/resources?limit=${SPARK_SAMPLES}`)
      .then((res) => {
        // A stop while the fetch was in flight already cleared the charts —
        // don't resurrect samples from the previous run.
        if (cancelled || !Array.isArray(res.history) || !ACTIVE_STATUSES.includes(statusRef.current)) return
        setSparkSamples((live) => {
          const firstLiveTs = live[0]?.ts ?? Infinity
          const seeded = res.history
            .filter((h) => h.ts < firstLiveTs)
            .map((h) => ({ ts: h.ts, cpu: h.cpuPct, mem: h.memBytes }))
          return [...seeded, ...live].slice(-SPARK_SAMPLES)
        })
      })
      .catch(() => undefined)
    return () => {
      cancelled = true
    }
  }, [server.id])

  // Collect sparkline history from live resources (charts clear on stop/crash)
  useEffect(() => {
    const snap = server.resources
    if (snap && ACTIVE_STATUSES.includes(server.status)) {
      setSparkSamples((prev) => {
        // The seeded history may already end with this exact sample.
        if (prev.length > 0 && prev[prev.length - 1].ts >= snap.ts) return prev
        return [...prev.slice(-(SPARK_SAMPLES - 1)), { ts: snap.ts, cpu: snap.cpuPct, mem: snap.memBytes }]
      })
    } else if (server.status === 'offline' || server.status === 'crashed') {
      setSparkSamples((prev) => (prev.length > 0 ? [] : prev))
    }
  }, [server.resources, server.status])

  const cpuSpark = useMemo(() => sparkSamples.map((s) => s.cpu), [sparkSamples])
  const memSpark = useMemo(() => sparkSamples.map((s) => s.mem), [sparkSamples])

  const running = server.status === 'running' || server.status === 'starting'

  // Display-only filter — Terminal does the actual filtering (filter prop),
  // the buffer itself is untouched. The deferred mirror keeps keystrokes
  // snappy while a large scrollback re-renders; counter and rendered lines
  // both read the deferred value so they always agree.
  const deferredFilter = useDeferredValue(filter)
  const query = deferredFilter.trim().toLowerCase()
  const filterActive = query.length > 0
  const matchCount = useMemo(() => {
    if (!query) return lines.length
    let n = 0
    for (const l of lines) if (l.line.toLowerCase().includes(query)) n++
    return n
  }, [lines, query])

  // "/" focuses the console search while this tab is mounted — with the same
  // input guard as Layout's "?" so typing a slash in any field stays typing.
  useEffect(() => {
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey) return
      const el = e.target
      if (el instanceof HTMLElement && (el.isContentEditable || el.closest('input, textarea, select'))) return
      if (document.querySelector('[role="dialog"]')) return
      e.preventDefault()
      searchRef.current?.focus()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const toggleTimestamps = () => {
    setShowTimestamps((prev) => {
      const next = !prev
      localStorage.setItem(TIMESTAMPS_KEY, next ? '1' : '0')
      return next
    })
  }

  const downloadLog = () => {
    const blob = new Blob([buildLogText(lines)], { type: 'text/plain' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    const d = new Date()
    const name = server.name.replace(/[^\w.-]+/g, '_')
    a.href = url
    a.download = `${name}-console-${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}.txt`
    a.click()
    URL.revokeObjectURL(url)
  }

  const players = server.query?.players
  // Non-empty list always shows; an empty list only means "nobody online" while
  // the server is actually up — otherwise (or when the field is absent) hide.
  const showPlayers = players !== undefined && (players.length > 0 || (server.status === 'running' && server.query?.online === true))

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    const cmd = command.trim()
    if (!cmd) return
    history.current = [cmd, ...history.current.slice(0, 49)]
    historyIdx.current = -1
    setCommand('')
    try {
      await sendCommand(cmd)
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    }
  }

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowUp') {
      e.preventDefault()
      const next = Math.min(historyIdx.current + 1, history.current.length - 1)
      if (history.current[next] !== undefined) {
        historyIdx.current = next
        setCommand(history.current[next])
      }
    } else if (e.key === 'ArrowDown') {
      e.preventDefault()
      const next = historyIdx.current - 1
      historyIdx.current = Math.max(next, -1)
      setCommand(next < 0 ? '' : history.current[next])
    }
  }

  const memLimit = server.memoryLimitMb ? server.memoryLimitMb * 1024 * 1024 : null

  return (
    <div className="space-y-3">
      {/* Stats strip — one row of four compact cells below sm so the terminal
          and its prompt fit a phone screen; 2×2 only on small landscape
          phones (sm..md), back to 4-up from md (tablets have the width —
          2×2 there is half-empty boxes). */}
      <div className="stagger grid grid-cols-4 gap-3 sm:grid-cols-2 md:grid-cols-4">
        <StatBox
          label={t('console.cpu')}
          value={running && server.resources ? `${server.resources.cpuPct.toFixed(1)}%` : '—'}
          spark={running ? cpuSpark : undefined}
          sparkMax={100}
        />
        <StatBox
          label={t('console.memory')}
          value={
            running && server.resources
              ? memLimit
                ? // memoryLimitMb is the configured allocation (e.g. Java heap),
                  // not a hard cap — process RSS can legitimately exceed it, so
                  // avoid a "used / max" reading.
                  t('console.memOfAlloc', { used: formatBytes(server.resources.memBytes), alloc: formatBytes(memLimit) })
                : formatBytes(server.resources.memBytes)
              : '—'
          }
          spark={running ? memSpark : undefined}
          sparkMax={memLimit ?? hostMemTotal ?? undefined}
        />
        <StatBox label={t('console.uptime')} value={running ? formatUptime(server.uptimeS) : '—'} />
        <StatBox
          label={t('console.playersNow')}
          value={server.query?.online ? `${server.query.playersOnline ?? 0}/${server.query.playersMax ?? '?'}` : '—'}
        />
      </div>

      {/* Install banners */}
      {server.status === 'installing' && (
        <div className="glass-subtle rounded-xl border-accent/30 bg-accent/10 px-3.5 py-2.5 text-[0.8125rem] text-accent">{t('console.installing')}</div>
      )}
      {server.status === 'install_failed' && (
        <div className="glass-subtle rounded-xl border-danger/30 bg-danger/10 px-3.5 py-2.5 text-[0.8125rem] text-danger">
          {t('console.installFailed')}
          {server.installError && <div className="mt-1 font-mono text-xs opacity-90">{server.installError}</div>}
        </div>
      )}
      {!server.installed && server.status === 'offline' && (
        <div className="glass-subtle rounded-xl border-warn/30 bg-warn/10 px-3.5 py-2.5 text-[0.8125rem] text-warn">{t('console.notInstalled')}</div>
      )}

      {/* Terminal + players sidebar */}
      <div className={cx('grid gap-3', showPlayers && 'lg:grid-cols-[minmax(0,1fr)_260px]')}>
        <Card className="overflow-hidden">
          <div className="flex items-center gap-2 border-b border-line/60 bg-elevated/40 px-3 py-2">
            <div className="relative max-w-56 flex-1">
              <Search size={12} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
              <input
                ref={searchRef}
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Escape') {
                    setFilter('')
                    e.currentTarget.blur()
                  }
                }}
                placeholder={t('console.searchPlaceholder')}
                aria-label={t('console.searchPlaceholder')}
                className={cx(
                  'glass-subtle h-8 w-full rounded-full pl-8 text-xs text-text placeholder:text-muted/60 focus:border-accent/60 focus:outline-none focus:ring-2 focus:ring-accent/30',
                  filter ? 'pr-8' : 'pr-3',
                )}
              />
              {filter && (
                <button
                  type="button"
                  onClick={() => {
                    setFilter('')
                    searchRef.current?.focus()
                  }}
                  aria-label={t('console.clearFilter')}
                  title={t('console.clearFilter')}
                  className="pressable absolute right-2 top-1/2 -translate-y-1/2 rounded-full p-1 text-muted hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
                >
                  <X size={12} />
                </button>
              )}
            </div>
            <span className="tabular ml-auto whitespace-nowrap font-mono text-[0.6875rem] text-muted/70">
              {filterActive
                ? t('console.matchCount', { x: matchCount, y: lines.length })
                : t('console.lineCount', { n: lines.length })}
            </span>
            {/* Hidden below sm alongside the gutter it controls (phones never
                show panel timestamps, so the toggle would be a no-op there). */}
            <IconButton
              label={t('console.timestamps')}
              size="sm"
              aria-pressed={showTimestamps}
              onClick={toggleTimestamps}
              className={cx('max-sm:hidden', showTimestamps && 'text-accent')}
            >
              <Clock size={14} />
            </IconButton>
            <IconButton label={t('console.download')} size="sm" onClick={downloadLog} disabled={lines.length === 0}>
              <Download size={14} />
            </IconButton>
          </div>
          {/* 34dvh below sm: together with the compact hero/stat strip this
              keeps terminal + prompt above the dock on a 390×844 screen. */}
          <Terminal lines={lines} filter={deferredFilter} showTimestamps={showTimestamps} className="h-[34dvh] min-h-64 sm:h-[46vh]" />
          {can('server.command') && (
            <form onSubmit={submit} className="flex items-center gap-2 border-t border-line/60 bg-elevated/40 py-2 pl-3 pr-2">
              <ChevronRight size={15} className="shrink-0 text-accent" />
              <Input
                value={command}
                onChange={(e) => setCommand(e.target.value)}
                onKeyDown={onKeyDown}
                placeholder={t('console.placeholder')}
                disabled={!running}
                className="h-11 border-0 bg-transparent font-mono text-[13px] focus:bg-transparent focus:ring-0"
              />
              {server.commandTransport === 'rcon' && (
                <Badge title={t('console.rconHint')} className="shrink-0 cursor-help border-accent/30 bg-accent/10 uppercase tracking-wide text-accent">
                  {t('console.rcon')}
                </Badge>
              )}
              <Button
                type="submit"
                variant="primary"
                disabled={!running || !command.trim()}
                aria-label={t('console.send')}
                title={t('console.send')}
                className="w-9 shrink-0 px-0"
              >
                <SendHorizonal size={14} />
              </Button>
            </form>
          )}
        </Card>
        {showPlayers && players && <PlayersCard players={players} />}
      </div>
    </div>
  )
}
