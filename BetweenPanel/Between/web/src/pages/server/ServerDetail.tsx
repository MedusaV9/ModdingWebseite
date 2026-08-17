import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { Link, NavLink, Route, Routes, useNavigate, useParams } from 'react-router-dom'
import { AlertTriangle, ArrowLeft, Boxes, Check, Container, Copy, Lock, Play, RotateCw, SearchX, Square, Zap } from 'lucide-react'
import { api, ApiError } from '../../api/client.ts'
import { wsClient } from '../../api/ws.ts'
import type { ConsoleLine, QueryResult, ResourceSnapshot, ServerDetail as ServerDetailType, ServerStatus } from '../../api/types.ts'
import { useT } from '../../i18n/index.tsx'
import { useToast } from '../../state/ToastContext.tsx'
import { Badge, Button, EmptyState, IconButton, Skeleton, cx } from '../../components/ui.tsx'
import { StatusPill } from '../../components/StatusPill.tsx'
import { GameIcon } from '../../components/GameIcon.tsx'
import { ConfirmModal } from '../../components/Modal.tsx'
import { ConsoleTab } from './ConsoleTab.tsx'
import { ShellTab } from './ShellTab.tsx'
import { FilesTab } from './FilesTab.tsx'
import { ModsTab } from './ModsTab.tsx'
import { ConfigTab } from './ConfigTab.tsx'
import { BackupsTab } from './BackupsTab.tsx'
import { SchedulesTab } from './SchedulesTab.tsx'
import { UsersTab } from './UsersTab.tsx'
import { ActivityTab } from './ActivityTab.tsx'
import { SettingsTab } from './SettingsTab.tsx'
import { CloneModal } from './CloneModal.tsx'

const MAX_LINES = 2000

interface ServerCtxValue {
  server: ServerDetailType
  lines: ConsoleLine[]
  refresh: () => Promise<unknown>
  patchServer: (patch: Partial<ServerDetailType>) => void
  power: (action: 'start' | 'stop' | 'restart' | 'kill') => Promise<void>
  sendCommand: (command: string) => Promise<void>
  busyPower: string | null
  /** Effective permission check for the current user on this server. */
  can: (perm: string) => boolean
}

const ServerCtx = createContext<ServerCtxValue | null>(null)

/**
 * Load errors are keyed by the server id they belong to: a render can happen
 * between a route change and the id-change reset effect, so an error recorded
 * for server A must never flash while server B's URL is already active.
 */
interface LoadError {
  id: string
  message: string
  status: number | null
}

export function useServer(): ServerCtxValue {
  const ctx = useContext(ServerCtx)
  if (!ctx) throw new Error('useServer outside ServerDetail')
  return ctx
}

// Console (index) is the landing tab and only needs server.view;
// every other tab is hidden unless the user holds the matching permission.
const TABS = [
  { path: '', key: 'tab.console', perm: null },
  // Shell only renders for docker-runtime servers (filtered below).
  { path: 'shell', key: 'tab.shell', perm: 'server.config' },
  { path: 'files', key: 'tab.files', perm: 'server.files.read' },
  // Always visible when permitted — ModsTab itself renders the unsupported
  // empty state for games without a mods block in their blueprint.
  { path: 'mods', key: 'tab.mods', perm: 'server.files.read' },
  { path: 'config', key: 'tab.config', perm: 'server.config' },
  { path: 'backups', key: 'tab.backups', perm: 'server.backups' },
  { path: 'schedules', key: 'tab.schedules', perm: 'server.schedules' },
  { path: 'users', key: 'tab.users', perm: 'server.users' },
  { path: 'activity', key: 'tab.activity', perm: 'server.activity' },
  { path: 'settings', key: 'tab.settings', perm: 'server.config' },
] as const

// Tabs whose ENTIRE surface is unsupported for remote servers in this round
// (shell/config/mods have no working operation; schedules can never exist) —
// hidden instead of shown as dead husks. Settings stays: it explains the
// remote situation and its delete action works through the gateway.
const REMOTE_HIDDEN_TABS: ReadonlySet<string> = new Set(['shell', 'mods', 'config', 'schedules'])

/**
 * Content-shaped loading state: mirrors the hero header, tab strip and the
 * console landing tab (stats strip + terminal card) so the swap doesn't jump.
 */
function ServerDetailSkeleton() {
  return (
    <div className="fade-in-up" aria-busy="true">
      <div className="glass mb-5 rounded-2xl p-4 sm:p-5">
        <div className="flex flex-wrap items-center gap-3">
          <Skeleton className="h-9 w-9" />
          <Skeleton className="h-10 w-10" />
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2.5">
              <Skeleton className="h-7 w-44 max-w-full rounded-full" />
              <Skeleton className="h-7.5 w-24 rounded-full" />
            </div>
            <Skeleton className="mt-1.5 h-3.5 w-56 max-w-full rounded-full" />
          </div>
          <div className="flex flex-wrap items-center gap-1.5 max-sm:basis-full">
            <Skeleton className="h-9 w-20" />
            <Skeleton className="h-9 w-24" />
            <Skeleton className="h-9 w-20" />
            <Skeleton className="h-9 w-9" />
          </div>
        </div>
      </div>
      <div className="mb-5 pb-1">
        <div className="glass-subtle inline-flex max-w-full items-center gap-1 overflow-hidden rounded-full p-1">
          {[0, 1, 2, 3, 4, 5, 6, 7].map((i) => (
            <Skeleton key={i} className="h-9 w-20 shrink-0 rounded-full" />
          ))}
        </div>
      </div>
      <div className="space-y-3">
        <div className="stagger grid grid-cols-4 gap-3 sm:grid-cols-2 md:grid-cols-4">
          {[0, 1, 2, 3].map((i) => (
            <Skeleton key={i} className="fade-in-up h-15" />
          ))}
        </div>
        <div className="glass overflow-hidden rounded-2xl">
          <div className="border-b border-line/60 bg-elevated/40 px-3 py-2">
            <Skeleton className="h-8 max-w-56 rounded-full" />
          </div>
          <Skeleton className="h-[34dvh] min-h-64 w-full rounded-none border-0 sm:h-[46vh]" />
          <div className="flex h-15 items-center gap-2 border-t border-line/60 bg-elevated/40 py-2 pl-3 pr-2">
            <Skeleton className="h-4 w-4 rounded-full" />
            <Skeleton className="h-4 w-56 max-w-full rounded-full" />
          </div>
        </div>
      </div>
    </div>
  )
}

// seq restarts at 1 with every panel restart — pair it with ts so lines from
// before and after a restart can never collide.
const lineKey = (l: ConsoleLine) => (l.seq !== undefined ? `${l.ts}#${l.seq}` : `${l.ts}|${l.stream}|${l.line}`)

function dedupeMerge(backlog: ConsoleLine[], live: ConsoleLine[]): ConsoleLine[] {
  // Live WS lines received while the backlog request was in flight may
  // already be part of the backlog snapshot — drop those duplicates.
  const seen = new Set(backlog.map(lineKey))
  return [...backlog, ...live.filter((l) => !seen.has(lineKey(l)))].slice(-MAX_LINES)
}

export function ServerDetail() {
  const { id = '' } = useParams()
  const t = useT()
  const toast = useToast()
  const navigate = useNavigate()
  const [server, setServer] = useState<ServerDetailType | null>(null)
  const [perms, setPerms] = useState<string[]>([])
  const [error, setError] = useState<LoadError | null>(null)
  const [lines, setLines] = useState<ConsoleLine[]>([])
  const [busyPower, setBusyPower] = useState<string | null>(null)
  const [killConfirm, setKillConfirm] = useState(false)
  const [cloneOpen, setCloneOpen] = useState(false)
  const [addressCopied, setAddressCopied] = useState(false)
  const copiedTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)
  const linesLoaded = useRef(false)
  // Guards against a slow response for server A overwriting state after the
  // user already navigated to server B.
  const idRef = useRef(id)
  idRef.current = id

  const refresh = useCallback(async (): Promise<string[] | null> => {
    try {
      const res = await api.get<{ server: ServerDetailType; myPermissions?: string[] }>(`/api/servers/${id}`)
      if (idRef.current !== id) return null
      setServer(res.server)
      setPerms(res.myPermissions ?? [])
      setError(null)
      return res.myPermissions ?? []
    } catch (err) {
      if (idRef.current === id) {
        setError({ id, message: (err as Error).message, status: err instanceof ApiError ? err.status : null })
      }
      return null
    }
  }, [id])

  const patchServer = useCallback((patch: Partial<ServerDetailType>) => {
    setServer((prev) => (prev ? { ...prev, ...patch } : prev))
  }, [])

  const can = useCallback((perm: string) => perms.includes(perm), [perms])

  /** Fetch the server-side console ring buffer and merge it with live lines. */
  const reloadBacklog = useCallback(async () => {
    try {
      const res = await api.get<{ lines: ConsoleLine[] }>(`/api/servers/${id}/console?limit=800`)
      if (idRef.current === id) setLines((live) => dedupeMerge(res.lines, live))
    } catch {
      /* backlog is best-effort */
    }
  }, [id])

  // Initial load + console backlog (only with console permission)
  useEffect(() => {
    let cancelled = false
    linesLoaded.current = false
    setLines([])
    setServer(null)
    setPerms([])
    setError(null)
    void (async () => {
      const myPerms = await refresh()
      if (cancelled || !myPerms || !myPerms.includes('server.console')) {
        linesLoaded.current = true
        return
      }
      await reloadBacklog()
      linesLoaded.current = true
    })()
    return () => {
      cancelled = true
    }
  }, [id, refresh, reloadBacklog])

  // WS: console channel + live status/stats/query
  useEffect(() => {
    const channel = `console:${id}`
    wsClient.subscribe(channel)
    const off = wsClient.onMessage((msg) => {
      if (msg.serverId !== id) {
        if (msg.t === '_open') {
          // Reconnected: refetch state AND the console backlog — lines
          // emitted while the socket was down never reached this client.
          void refresh()
          if (linesLoaded.current && perms.includes('server.console')) void reloadBacklog()
        }
        return
      }
      if (msg.t === 'console') {
        setLines((prev) => [...prev, msg.line as ConsoleLine].slice(-MAX_LINES))
      } else if (msg.t === 'deleted') {
        toast('info', t('toast.serverDeleted'))
        navigate('/servers', { replace: true })
      } else if (msg.t === 'status') {
        const status = msg.status as ServerStatus
        setServer((prev) => {
          if (!prev) return prev
          const installed = status === 'offline' && prev.status === 'installing' ? true : prev.installed
          return { ...prev, status, installed, installError: status === 'install_failed' ? prev.installError : null }
        })
        if (status === 'install_failed' || status === 'offline') void refresh()
      } else if (msg.t === 'stats') {
        const snap = msg.snap as ResourceSnapshot
        setServer((prev) => (prev ? { ...prev, resources: snap, uptimeS: snap.uptimeS } : prev))
      } else if (msg.t === 'query') {
        setServer((prev) => (prev ? { ...prev, query: msg.query as QueryResult } : prev))
      }
    })
    return () => {
      off()
      wsClient.unsubscribe(channel)
    }
  }, [id, refresh, reloadBacklog, perms, navigate, toast, t])

  const power = useCallback(
    async (action: 'start' | 'stop' | 'restart' | 'kill') => {
      setBusyPower(action)
      try {
        await api.post(`/api/servers/${id}/power`, { action })
      } catch (err) {
        toast('error', err instanceof ApiError ? err.message : String(err))
      } finally {
        setBusyPower(null)
      }
    },
    [id, toast],
  )

  const sendCommand = useCallback(
    async (command: string) => {
      await api.post(`/api/servers/${id}/command`, { command })
    },
    [id],
  )

  // Same fallback logic as Account's copy helper: self-hosted panels often run
  // over plain http:// (a non-secure context) where navigator.clipboard is
  // undefined — execCommand keeps "copy address" working there. Success is
  // signalled by the quieter icon swap (Check) instead of a toast.
  const copyAddress = useCallback(
    async (text: string) => {
      try {
        if (navigator.clipboard?.writeText) {
          await navigator.clipboard.writeText(text)
        } else {
          const ta = document.createElement('textarea')
          ta.value = text
          ta.style.position = 'fixed'
          ta.style.opacity = '0'
          document.body.appendChild(ta)
          ta.focus()
          ta.select()
          const ok = document.execCommand('copy')
          document.body.removeChild(ta)
          if (!ok) throw new Error('copy failed')
        }
        setAddressCopied(true)
        clearTimeout(copiedTimer.current)
        copiedTimer.current = setTimeout(() => setAddressCopied(false), 1500)
      } catch {
        toast('error', t('common.copyFailed'))
      }
    },
    [toast, t],
  )

  useEffect(() => () => clearTimeout(copiedTimer.current), [])

  const value = useMemo(
    () => (server ? { server, lines, refresh, patchServer, power, sendCommand, busyPower, can } : null),
    [server, lines, refresh, patchServer, power, sendCommand, busyPower, can],
  )

  // Render-time guard against stale errors: only an error recorded for the
  // CURRENT id counts (the id-change reset effect runs after paint, so a
  // one-frame flash of the previous server's error would otherwise be possible).
  const shownError = error && error.id === id ? error : null

  // Full-page error ONLY while nothing is loaded — a transient refresh failure
  // (WS reconnect, brief network blip) on an already-displayed server must not
  // blank the page; the next successful refresh clears the error silently.
  if (shownError && !server) {
    const notFound = shownError.status === 404
    return (
      <div className="fade-in-up flex justify-center pt-6 sm:pt-12">
        <div className="glass w-full max-w-md rounded-2xl px-6 py-10 text-center">
          <div className="glass-subtle mx-auto w-fit rounded-2xl p-4 text-muted/60">
            {notFound ? <SearchX size={32} /> : <AlertTriangle size={32} />}
          </div>
          <h1 className="mt-5 font-display text-lg font-bold tracking-tight">
            {notFound ? t('server.notFoundTitle') : t('server.loadErrorTitle')}
          </h1>
          <p className="mx-auto mt-1.5 max-w-xs text-sm leading-relaxed text-muted">
            {notFound ? t('server.notFoundBody') : shownError.message}
          </p>
          <Link to="/servers" className="mt-6 inline-block">
            {/* Not-found CTA convention (shared with the global 404): primary, md. */}
            <Button variant="primary">
              <ArrowLeft size={14} />
              {t('server.backToServers')}
            </Button>
          </Link>
        </div>
      </div>
    )
  }
  if (!value || !server) return <ServerDetailSkeleton />

  const remote = server.nodeId != null
  const mayPower = can('server.power')
  const canStart = mayPower && ['offline', 'crashed'].includes(server.status) && server.installed && !server.suspended
  const canStop = mayPower && ['running', 'starting'].includes(server.status)
  const gamePort = server.ports[0]
  const visibleTabs = TABS.filter(
    (tab) =>
      (tab.perm === null || can(tab.perm)) &&
      (tab.path !== 'shell' || server.runtime === 'docker') &&
      (!remote || !REMOTE_HIDDEN_TABS.has(tab.path)),
  )
  const guard = (perm: string | null, el: ReactNode) =>
    perm === null || can(perm) ? el : <EmptyState icon={<Lock size={20} />} title={t('perm.missing')} />
  // Deep links to remote-hidden tabs get the quiet explanation, not a husk.
  const remoteGuard = (perm: string | null, el: ReactNode) =>
    remote ? <EmptyState icon={<Boxes size={20} />} title={t('remote.hint')} /> : guard(perm, el)

  return (
    <ServerCtx.Provider value={value}>
      <div className="fade-in-up">
        {/* Hero header */}
        <div className="glass mb-5 rounded-2xl p-4 sm:p-5">
          <div className="flex flex-wrap items-center gap-3">
            <Link
              to="/servers"
              aria-label={t('server.backToServers')}
              title={t('server.backToServers')}
              className="ui-control icon-btn pressable glass-subtle inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-muted hover:bg-elevated/70 hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
            >
              <ArrowLeft size={16} />
            </Link>
            <GameIcon icon={server.icon} color={server.color} boxed size={26} />
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-2.5">
                <h1 className="truncate font-display text-xl font-bold tracking-tight">{server.name}</h1>
                <StatusPill status={server.status} />
                {remote && (
                  <Badge title={t('servers.nodeBadge', { name: server.nodeName ?? '' })}>
                    <Boxes size={11} />
                    {server.nodeName}
                  </Badge>
                )}
                {server.runtime === 'docker' && (
                  <span
                    className="glass-subtle inline-flex items-center gap-1 rounded-full border-accent2/30 bg-accent2/10 px-2 py-0.5 text-[0.625rem] font-bold uppercase tracking-wide text-accent2"
                    title={server.dockerImageEffective ?? 'Docker'}
                  >
                    <Container size={11} />
                    Docker
                  </span>
                )}
              </div>
              <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted">
                <span>{server.blueprintName}</span>
                {gamePort && (
                  <>
                    <span aria-hidden>·</span>
                    <span className="tabular font-mono">
                      {location.hostname}:{gamePort.port}
                    </span>
                    {/* Negative margin keeps the 32px button from inflating the
                        text-xs meta line; coarse pointers still get 44px. */}
                    <IconButton
                      label={addressCopied ? t('common.copied') : t('server.copyAddress')}
                      size="sm"
                      className="-my-1"
                      onClick={() => void copyAddress(`${location.hostname}:${gamePort.port}`)}
                    >
                      {addressCopied ? <Check size={13} className="text-success" /> : <Copy size={13} />}
                    </IconButton>
                  </>
                )}
                {server.query?.online && (
                  <>
                    <span aria-hidden>·</span>
                    <span className="tabular">
                      {server.query.playersOnline ?? 0}/{server.query.playersMax ?? '?'} {t('servers.players')}
                    </span>
                  </>
                )}
              </div>
            </div>
            {/* Power actions collapse to icon-only below sm so the hero stays
                compact enough for terminal + prompt to fit one phone screen.
                basis-full gives them their own wrap row there — otherwise the
                narrow cluster would squeeze the flex-1 title to nothing. */}
            <div className="flex flex-wrap items-center gap-1.5 max-sm:basis-full">
              <Button
                variant="success"
                disabled={!canStart}
                loading={busyPower === 'start'}
                onClick={() => void power('start')}
                aria-label={t('console.start')}
                title={t('console.start')}
              >
                <Play size={14} />
                <span className="max-sm:hidden">{t('console.start')}</span>
              </Button>
              <Button
                variant="secondary"
                disabled={!canStop}
                loading={busyPower === 'restart'}
                onClick={() => void power('restart')}
                aria-label={t('console.restart')}
                title={t('console.restart')}
              >
                <RotateCw size={14} />
                <span className="max-sm:hidden">{t('console.restart')}</span>
              </Button>
              <Button
                variant="danger"
                disabled={!canStop}
                loading={busyPower === 'stop'}
                onClick={() => void power('stop')}
                aria-label={t('console.stop')}
                title={t('console.stop')}
              >
                <Square size={14} />
                <span className="max-sm:hidden">{t('console.stop')}</span>
              </Button>
              <IconButton
                label={t('console.kill')}
                disabled={!mayPower || server.status === 'offline' || server.status === 'node-offline'}
                loading={busyPower === 'kill'}
                onClick={() => setKillConfirm(true)}
              >
                <Zap size={14} />
              </IconButton>
              {/* Cloning is a local-only operation in this round. */}
              {can('owner') && !remote && ['offline', 'crashed'].includes(server.status) && (
                <IconButton label={t('clone.title')} onClick={() => setCloneOpen(true)}>
                  <Copy size={14} />
                </IconButton>
              )}
            </div>
          </div>
        </div>

        {/* Tabs — glass pill strip; scrolls horizontally without a visible
            scrollbar (the global scrollbar styling lives in @layer base, so
            plain utilities override it). On coarse pointers a trailing-edge
            mask fade (same treatment as .table-scroll) hints that the strip
            keeps going where it clips. */}
        <div className="mb-5 overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden [@media(pointer:coarse)]:[-webkit-mask-image:linear-gradient(to_right,#000_calc(100%_-_24px),rgba(0,0,0,0.35))] [@media(pointer:coarse)]:[mask-image:linear-gradient(to_right,#000_calc(100%_-_24px),rgba(0,0,0,0.35))]">
          <div className="glass-subtle inline-flex min-w-full items-center gap-1 rounded-full p-1 sm:min-w-0">
            {visibleTabs.map((tab) => (
              <NavLink
                key={tab.path}
                to={tab.path === '' ? `/servers/${id}` : `/servers/${id}/${tab.path}`}
                end={tab.path === ''}
                className={({ isActive }) =>
                  cx(
                    'ui-control pressable inline-flex shrink-0 items-center justify-center whitespace-nowrap rounded-full px-3.5 py-2 text-[0.8125rem] font-medium',
                    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
                    isActive ? 'sheen bg-accent/15 text-accent' : 'text-muted hover:bg-elevated/60 hover:text-text',
                  )
                }
              >
                {t(tab.key)}
              </NavLink>
            ))}
          </div>
        </div>

        <Routes>
          <Route index element={<ConsoleTab />} />
          <Route path="shell" element={remoteGuard('server.config', <ShellTab />)} />
          <Route path="files" element={guard('server.files.read', <FilesTab />)} />
          <Route path="mods" element={remoteGuard('server.files.read', <ModsTab />)} />
          <Route path="config" element={remoteGuard('server.config', <ConfigTab />)} />
          <Route path="backups" element={guard('server.backups', <BackupsTab />)} />
          <Route path="schedules" element={remoteGuard('server.schedules', <SchedulesTab />)} />
          <Route path="users" element={guard('server.users', <UsersTab />)} />
          <Route path="activity" element={guard('server.activity', <ActivityTab />)} />
          <Route path="settings" element={guard('server.config', <SettingsTab />)} />
        </Routes>

        <ConfirmModal
          open={killConfirm}
          onClose={() => setKillConfirm(false)}
          onConfirm={() => {
            setKillConfirm(false)
            void power('kill')
          }}
          message={t('console.killConfirm')}
          danger
          confirmLabel={t('console.kill')}
        />

        <CloneModal open={cloneOpen} onClose={() => setCloneOpen(false)} />
      </div>
    </ServerCtx.Provider>
  )
}
