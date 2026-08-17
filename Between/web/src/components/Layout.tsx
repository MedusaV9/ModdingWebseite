import { useEffect, useRef, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import {
  LayoutDashboard, Server, Package, LibraryBig, Palette, UserCircle, Users, ScrollText, Settings2,
  LogOut, Menu, X, PlusCircle, Search, CircleHelp, Network,
} from 'lucide-react'
import { useAuth } from '../state/AuthContext.tsx'
import { useT } from '../i18n/index.tsx'
import { cx, IconButton } from './ui.tsx'
import { CommandPalette } from './CommandPalette.tsx'
import { ShortcutsHelp } from './ShortcutsHelp.tsx'
import type { ReactNode } from 'react'

function NavItem({ to, icon, label, end, onClick }: { to: string; icon: ReactNode; label: string; end?: boolean; onClick?: () => void }) {
  return (
    <NavLink
      to={to}
      end={end}
      onClick={onClick}
      className={({ isActive }) =>
        cx(
          'pressable flex items-center gap-2.5 rounded-xl px-3 py-2 text-[0.8125rem] font-medium',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
          isActive ? 'sheen bg-accent/15 text-accent' : 'text-muted hover:bg-elevated/60 hover:text-text',
        )
      }
    >
      {icon}
      {label}
    </NavLink>
  )
}

function SectionLabel({ children }: { children: ReactNode }) {
  // Full-strength muted: alpha-reduced muted fails WCAG contrast on light themes.
  return <div className="mb-1 mt-5 px-3 text-[0.625rem] font-bold uppercase tracking-[0.14em] text-muted">{children}</div>
}

/** Bottom-dock tab (mobile): icon + tiny label, accent pill when active. */
function DockLink({ to, end, icon, label }: { to: string; end?: boolean; icon: ReactNode; label: string }) {
  return (
    <NavLink
      to={to}
      end={end}
      className={({ isActive }) =>
        cx(
          'pressable flex min-w-0 flex-1 flex-col items-center justify-center gap-0.5 rounded-full px-2 py-1.5 text-[0.625rem] font-semibold',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
          isActive ? 'bg-accent/15 text-accent' : 'text-muted',
        )
      }
    >
      {icon}
      <span className="max-w-full truncate">{label}</span>
    </NavLink>
  )
}

export function Layout() {
  const { user, meta, logout } = useAuth()
  const t = useT()
  const navigate = useNavigate()
  const location = useLocation()
  const [mobileOpen, setMobileOpen] = useState(false)
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [helpOpen, setHelpOpen] = useState(false)
  const mainRef = useRef<HTMLElement | null>(null)
  const isAdmin = user?.role === 'admin'
  const close = () => setMobileOpen(false)

  // Page-transition key: first three path segments, so switching tabs inside
  // /servers/:id/* does NOT remount the page (console state must survive).
  const pageKey = location.pathname.split('/').slice(0, 3).join('/') || '/'

  // Safety net on top of the NavItem onClick handlers: any route change
  // (palette, programmatic navigation) closes the drawer.
  useEffect(() => {
    setMobileOpen(false)
  }, [location.pathname])

  // New page → start at the top (instant: bypasses `main`'s smooth scrolling).
  useEffect(() => {
    mainRef.current?.scrollTo({ top: 0, behavior: 'instant' })
  }, [pageKey])

  // Global shortcuts: Ctrl/Cmd+K toggles the palette, "?" opens the shortcuts
  // help. "?" must never fire while typing (input guard) or on top of an open
  // dialog; the palette's search input keeps focus, so the guard covers it too.
  useEffect(() => {
    const isEditable = (el: EventTarget | null) =>
      el instanceof HTMLElement && (el.isContentEditable || el.closest('input, textarea, select') !== null)
    // Shared dialog guard (Modal AND the palette carry role="dialog").
    const hasOpenDialog = () => document.querySelector('[role="dialog"]') !== null
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        // Closing always works (the open dialog is the palette itself, short-
        // circuited by `v`); OPENING is blocked while another dialog is up —
        // palette navigation would unmount it and bypass a dirty modal's
        // discard confirmation.
        setPaletteOpen((v) => (v ? false : !hasOpenDialog()))
        return
      }
      if (e.key === '?' && !e.ctrlKey && !e.metaKey && !e.altKey) {
        if (isEditable(e.target) || hasOpenDialog()) return
        e.preventDefault()
        setHelpOpen(true)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const nav = (
    <nav className="flex h-full flex-col p-3">
      <div className="flex items-center justify-between px-2 py-2">
        <button
          onClick={() => { navigate('/'); close() }}
          className="pressable flex items-center gap-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40 rounded-lg"
        >
          <span className="glow-accent inline-flex h-8 w-8 items-center justify-center rounded-xl btn-gradient font-display text-sm font-bold">B</span>
          <span className="font-display text-lg font-bold tracking-tight">{meta?.panelName ?? 'Between'}</span>
        </button>
        <IconButton label={t('common.close')} size="sm" className="lg:hidden" onClick={close}>
          <X size={18} />
        </IconButton>
      </div>

      <button
        onClick={() => {
          close()
          setPaletteOpen(true)
        }}
        className={cx(
          'glass-subtle pressable mt-3 flex w-full items-center gap-2.5 rounded-xl px-3 py-2 text-[0.8125rem] text-muted',
          'hover:border-accent/40 hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
        )}
      >
        <Search size={14} />
        <span className="flex-1 text-left">{t('palette.trigger')}</span>
        {/* max-lg:hidden: this nav renders in the desktop rail AND the mobile
            drawer — the drawer only exists <lg, where a ⌘K hint is meaningless. */}
        <kbd className="rounded-lg border border-line/70 bg-surface/70 px-1.5 py-0.5 font-mono text-[0.625rem] font-semibold max-lg:hidden">⌘K</kbd>
      </button>

      <div className="mt-3 space-y-0.5">
        <NavItem to="/" end icon={<LayoutDashboard size={16} />} label={t('nav.dashboard')} onClick={close} />
        <NavItem to="/servers" end icon={<Server size={16} />} label={t('nav.servers')} onClick={close} />
        <NavItem to="/servers/new" end icon={<PlusCircle size={16} />} label={t('servers.create')} onClick={close} />
        <NavItem to="/blueprints" icon={<Package size={16} />} label={t('nav.blueprints')} onClick={close} />
        <NavItem to="/catalog" icon={<LibraryBig size={16} />} label={t('nav.catalog')} onClick={close} />
      </div>

      {isAdmin && (
        <>
          <SectionLabel>{t('nav.admin')}</SectionLabel>
          <div className="space-y-0.5">
            <NavItem to="/admin/nodes" icon={<Network size={16} />} label={t('nav.nodes')} onClick={close} />
            <NavItem to="/admin/users" icon={<Users size={16} />} label={t('nav.users')} onClick={close} />
            <NavItem to="/admin/audit" icon={<ScrollText size={16} />} label={t('nav.audit')} onClick={close} />
            <NavItem to="/admin/settings" icon={<Settings2 size={16} />} label={t('nav.settings')} onClick={close} />
          </div>
        </>
      )}

      <div className="flex-1" />

      <div className="space-y-0.5 border-t border-line/60 pt-3">
        <NavItem to="/appearance" icon={<Palette size={16} />} label={t('nav.appearance')} onClick={close} />
        <NavItem to="/account" icon={<UserCircle size={16} />} label={t('nav.account')} onClick={close} />
        <div className="glass-subtle mt-2 flex items-center justify-between rounded-xl px-3 py-2">
          <div className="min-w-0">
            <div className="truncate text-[0.8125rem] font-semibold">{user?.username}</div>
            <div className="text-[0.6875rem] text-muted">{user?.role === 'admin' ? t('users.role.admin') : t('users.role.user')}</div>
          </div>
          <div className="flex shrink-0 items-center">
            {/* Discoverable entry point for the "?" overlay — this nav renders
                in the desktop rail AND the mobile drawer, where no "?" key exists. */}
            <button
              onClick={() => {
                close()
                setHelpOpen(true)
              }}
              title={t('shortcuts.title')}
              aria-label={t('shortcuts.title')}
              className="pressable rounded-lg p-2 text-muted hover:bg-elevated/70 hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
            >
              <CircleHelp size={16} />
            </button>
            <button
              onClick={() => void logout()}
              title={t('nav.logout')}
              aria-label={t('nav.logout')}
              className="pressable rounded-lg p-2 text-muted hover:bg-danger/15 hover:text-danger focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
            >
              <LogOut size={16} />
            </button>
          </div>
        </div>
      </div>
    </nav>
  )

  return (
    <div className="app-bg flex h-full">
      {/* Skip link — FIRST focusable element in the frame. Parked above the
          viewport (fixed + translate) instead of sr-only so the focus:reveal
          never fights utility ordering; it drops in as a glass pill on focus. */}
      <a
        href="#main"
        onClick={(e) => {
          e.preventDefault()
          mainRef.current?.focus()
        }}
        className={cx(
          'glass-strong fixed left-4 top-4 z-[100] -translate-y-[200%] rounded-full px-4 py-2 text-[0.8125rem] font-semibold opacity-0 transition',
          'focus:translate-y-0 focus:opacity-100 focus:outline-none focus:ring-2 focus:ring-accent/40',
        )}
      >
        {t('a11y.skipToContent')}
      </a>
      {/* Desktop: floating glass rail, inset from the edge */}
      <aside className="hidden w-[16.5rem] shrink-0 p-3 pr-0 lg:block">
        <div className="glass h-full overflow-y-auto rounded-2xl">{nav}</div>
      </aside>

      {/* Mobile drawer (full nav incl. admin links) */}
      {mobileOpen && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <div className="fade-in absolute inset-0 bg-black/50 backdrop-blur-sm" onClick={close} />
          <aside className="glass-strong slide-in-left safe-top safe-bottom absolute inset-y-0 left-0 w-72 overflow-y-auto rounded-r-2xl border-y-0 border-l-0 md:w-80">
            {nav}
          </aside>
        </div>
      )}

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Mobile topbar */}
        <header className="glass-strong safe-top rounded-none border-x-0 border-t-0 lg:hidden">
          <div className="flex items-center gap-2 px-3 py-2">
            <IconButton label={t('nav.more')} onClick={() => setMobileOpen(true)}>
              <Menu size={20} />
            </IconButton>
            {/* Centered: both side controls are equal-width IconButtons, so
                optical centering between them is free (Apple topbar pattern). */}
            <span className="flex-1 truncate text-center font-display text-base font-bold tracking-tight">{meta?.panelName ?? 'Between'}</span>
            <IconButton label={t('palette.trigger')} onClick={() => setPaletteOpen(true)}>
              <Search size={18} />
            </IconButton>
          </div>
        </header>

        {/* scrollbar-gutter:stable — always reserve the scrollbar gutter so
            pages with/without overflow render content at identical widths
            (no 10px wiggle when switching server-detail tabs). */}
        {/* id + tabIndex=-1: programmatic focus target for the skip link
            (kept out of the tab order, no focus outline on the scroller). */}
        <main ref={mainRef} id="main" tabIndex={-1} className="min-h-0 flex-1 overflow-y-auto outline-none [scrollbar-gutter:stable]">
          {/* Keyed on pageKey (not full pathname): animates route changes
              without remounting on nested-tab navigation. */}
          <div key={pageKey} className="fade-in-up mx-auto w-full max-w-7xl px-[clamp(1rem,3vw,2.5rem)] pt-6 pb-28 lg:pt-8 lg:pb-10">
            <Outlet />
          </div>
        </main>
      </div>

      {/* Mobile bottom dock: floating glass pill, safe-area aware */}
      <nav className="pointer-events-none fixed inset-x-0 bottom-0 z-30 flex justify-center px-4 pb-[calc(env(safe-area-inset-bottom,0px)+0.75rem)] lg:hidden">
        {/* md:max-w-md — a touch more breathing room per tab on tablets,
            still a compact floating pill (never a full-width bar). */}
        <div className="glass-strong pointer-events-auto flex w-full max-w-sm items-stretch gap-1 rounded-full p-1.5 md:max-w-md">
          <DockLink to="/" end icon={<LayoutDashboard size={19} />} label={t('nav.dashboard')} />
          <DockLink to="/servers" icon={<Server size={19} />} label={t('nav.servers')} />
          <DockLink to="/catalog" icon={<LibraryBig size={19} />} label={t('nav.catalog')} />
          <button
            onClick={() => setMobileOpen(true)}
            className={cx(
              'pressable flex min-w-0 flex-1 flex-col items-center justify-center gap-0.5 rounded-full px-2 py-1.5 text-[0.625rem] font-semibold text-muted',
              'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
            )}
          >
            <Menu size={19} />
            <span className="max-w-full truncate">{t('nav.more')}</span>
          </button>
        </div>
      </nav>

      <CommandPalette open={paletteOpen} onClose={() => setPaletteOpen(false)} />
      <ShortcutsHelp open={helpOpen} onClose={() => setHelpOpen(false)} />
    </div>
  )
}
