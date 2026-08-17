/**
 * Global command palette (Ctrl/Cmd+K): jump to servers, pages and actions.
 * Rendered through a portal so no animated/transformed ancestor can trap the
 * fixed-position overlay (same rule as Modal).
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { useNavigate } from 'react-router-dom'
import {
  Activity,
  Boxes,
  Container,
  Gauge,
  LayoutDashboard,
  LibraryBig,
  Network,
  Palette,
  Plus,
  Search,
  Server as ServerIcon,
  Settings,
  UserRound,
  Users,
} from 'lucide-react'
import { useServerList } from '../state/useServers.ts'
import { useAuth } from '../state/AuthContext.tsx'
import { useT } from '../i18n/index.tsx'
import { StatusPill } from './StatusPill.tsx'
import { GameIcon } from './GameIcon.tsx'
import { cx, KeyboardHint } from './ui.tsx'

interface PaletteItem {
  id: string
  group: 'servers' | 'pages' | 'actions'
  label: string
  sub?: string
  icon: React.ReactNode
  trailing?: React.ReactNode
  to: string
  keywords: string
}

/**
 * Rendering groups results by kind in this order, so `results` must be laid
 * out the same way — `selected` indexes the flattened visual list.
 */
const GROUP_ORDER: PaletteItem['group'][] = ['servers', 'pages', 'actions']

/** startsWith > word-boundary > substring; -1 = no match. */
function score(haystack: string, query: string): number {
  const h = haystack.toLowerCase()
  const q = query.toLowerCase()
  if (!q) return 0
  const idx = h.indexOf(q)
  if (idx === -1) return -1
  if (idx === 0) return 3
  if (h[idx - 1] === ' ' || h[idx - 1] === '/') return 2
  return 1
}

export function CommandPalette({ open, onClose }: { open: boolean; onClose: () => void }) {
  const t = useT()
  const navigate = useNavigate()
  const { user } = useAuth()
  const { servers } = useServerList()
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState(0)
  const inputRef = useRef<HTMLInputElement>(null)
  const listRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (open) {
      setQuery('')
      setSelected(0)
      // Focus after the portal renders.
      requestAnimationFrame(() => inputRef.current?.focus())
    }
  }, [open])

  const items = useMemo<PaletteItem[]>(() => {
    const isAdmin = user?.role === 'admin'
    const list: PaletteItem[] = []
    for (const s of servers ?? []) {
      list.push({
        id: `server-${s.id}`,
        group: 'servers',
        label: s.name,
        sub: s.blueprintName,
        icon: <GameIcon icon={s.icon} color={s.color} size={16} boxed />,
        trailing: (
          <span className="flex items-center gap-1.5">
            {s.runtime === 'docker' && <Container size={12} className="text-accent2" />}
            <StatusPill status={s.status} size="sm" />
          </span>
        ),
        to: `/servers/${s.id}`,
        keywords: `${s.name} ${s.blueprintName} ${s.tags.join(' ')}`,
      })
    }
    const pages: [string, string, React.ReactNode, boolean][] = [
      [t('nav.dashboard'), '/', <LayoutDashboard key="i" size={16} />, true],
      [t('nav.servers'), '/servers', <ServerIcon key="i" size={16} />, true],
      [t('nav.blueprints'), '/blueprints', <Boxes key="i" size={16} />, true],
      [t('nav.catalog'), '/catalog', <LibraryBig key="i" size={16} />, true],
      [t('nav.appearance'), '/appearance', <Palette key="i" size={16} />, true],
      [t('nav.account'), '/account', <UserRound key="i" size={16} />, true],
      [t('nav.nodes'), '/admin/nodes', <Network key="i" size={16} />, isAdmin],
      [t('nav.users'), '/admin/users', <Users key="i" size={16} />, isAdmin],
      [t('nav.audit'), '/admin/audit', <Activity key="i" size={16} />, isAdmin],
      [t('nav.settings'), '/admin/settings', <Settings key="i" size={16} />, isAdmin],
    ]
    for (const [label, to, icon, visible] of pages) {
      if (visible) list.push({ id: `page-${to}`, group: 'pages', label, icon, to, keywords: `${label} ${to}` })
    }
    list.push({
      id: 'action-create',
      group: 'actions',
      label: t('create.title'),
      icon: <Plus size={16} />,
      to: '/servers/new',
      keywords: `${t('create.title')} new server create erstellen`,
    })
    return list
  }, [servers, user, t])

  const results = useMemo(() => {
    const q = query.trim()
    const scored = items
      .map((item) => ({ item, s: q ? score(item.keywords, q) : 0 }))
      .filter(({ s }) => s >= 0)
      .sort((a, b) => b.s - a.s)
      .map(({ item }) => item)
    // Score decides WHICH items make the cut (top-N)…
    const capped = q ? scored.slice(0, 12) : scored.slice(0, 16)
    // …but the list must match display order (grouped by kind, score order
    // kept within each group) so keyboard navigation walks it top-to-bottom.
    return GROUP_ORDER.flatMap((g) => capped.filter((item) => item.group === g))
  }, [items, query])

  useEffect(() => setSelected(0), [results.length, query])

  // Escape must close the palette no matter where focus sits: clicking
  // non-focusable panel padding moves focus to <body>, where the panel's
  // React onKeyDown never fires. Window-level, same pattern as Modal.
  useEffect(() => {
    if (!open) return
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  // Keep the selected row in view while arrowing through the list.
  useEffect(() => {
    listRef.current?.querySelector(`[data-idx="${selected}"]`)?.scrollIntoView({ block: 'nearest' })
  }, [selected])

  if (!open) return null

  const go = (item: PaletteItem) => {
    onClose()
    navigate(item.to)
  }

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setSelected((s) => Math.min(results.length - 1, s + 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setSelected((s) => Math.max(0, s - 1))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      const item = results[selected]
      if (item) go(item)
    }
  }

  const groupLabels: Record<PaletteItem['group'], string> = {
    servers: t('palette.servers'),
    pages: t('palette.pages'),
    actions: t('palette.actions'),
  }

  return createPortal(
    <div
      className="fade-in fixed inset-0 z-[90] flex items-start justify-center bg-black/50 p-4 pt-[12dvh] backdrop-blur-sm"
      onClick={onClose}
    >
      {/* role="dialog" is load-bearing beyond semantics: the global "?" and
          console "/" shortcuts check `[role="dialog"]` to avoid firing over
          an open overlay (focus can sit on <body> after a backdrop click). */}
      <div
        role="dialog"
        aria-modal="true"
        aria-label={t('shortcuts.groupPalette')}
        className="glass-strong scale-in flex max-h-[70dvh] w-full max-w-lg origin-top flex-col overflow-hidden rounded-2xl"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={onKeyDown}
      >
        <div className="flex h-11 shrink-0 items-center gap-2.5 border-b border-line/60 px-4">
          <Search size={16} className="shrink-0 text-muted" />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('palette.placeholder')}
            aria-label={t('palette.placeholder')}
            className="h-full w-full bg-transparent text-sm outline-none placeholder:text-muted/60"
            spellCheck={false}
          />
          <KeyboardHint>esc</KeyboardHint>
        </div>
        <div ref={listRef} className="min-h-0 flex-1 overflow-y-auto p-2">
          {results.length === 0 && (
            <div className="flex flex-col items-center gap-3 px-3 py-10 text-center">
              <span className="glass-subtle rounded-2xl p-3 text-muted/60">
                <Search size={18} />
              </span>
              <p className="text-sm text-muted">{t('palette.noResults')}</p>
            </div>
          )}
          {GROUP_ORDER.map((key) => {
            const groupItems = results.filter((r) => r.group === key)
            if (groupItems.length === 0) return null
            return (
              <div key={key} className="mb-1">
                <div className="px-3 pb-1 pt-2 text-[0.625rem] font-bold uppercase tracking-[0.14em] text-muted">{groupLabels[key]}</div>
                {groupItems.map((item) => {
                  const idx = results.indexOf(item)
                  const active = idx === selected
                  return (
                    <button
                      key={item.id}
                      data-idx={idx}
                      onClick={() => go(item)}
                      onMouseMove={() => setSelected(idx)}
                      className={cx(
                        'ui-control relative flex min-h-11 w-full items-center gap-3 rounded-xl px-3 py-1.5 text-left text-sm transition-colors',
                        active ? 'sheen bg-accent/20 text-text' : 'text-text/80',
                      )}
                    >
                      {/* Classic palette cue: a small accent bar marks the keyboard-selected row. */}
                      {active && (
                        <span
                          aria-hidden
                          className="absolute left-1 top-1/2 h-[60%] w-[3px] -translate-y-1/2 rounded-full bg-linear-to-b from-accent to-accent2"
                        />
                      )}
                      <span className={cx('shrink-0', active ? 'text-accent' : 'text-muted')}>{item.icon}</span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate font-medium">{item.label}</span>
                        {item.sub && <span className="block truncate text-[0.6875rem] text-muted">{item.sub}</span>}
                      </span>
                      {item.trailing}
                    </button>
                  )
                })}
              </div>
            )
          })}
        </div>
        <div className="flex shrink-0 items-center gap-3 border-t border-line/60 px-4 py-2 text-[0.625rem] text-muted/70">
          <span className="flex items-center gap-1">
            <Gauge size={11} />
            {t('palette.hintNav')}
          </span>
          <span className="ml-auto flex items-center gap-1">
            <KeyboardHint>↑↓</KeyboardHint>
            <KeyboardHint>↵</KeyboardHint>
          </span>
        </div>
      </div>
    </div>,
    document.body,
  )
}
