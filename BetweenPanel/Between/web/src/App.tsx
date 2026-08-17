import { Component, Suspense, lazy, useEffect } from 'react'
import type { ReactNode } from 'react'
import { Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { useAuth } from './state/AuthContext.tsx'
import { useToast } from './state/ToastContext.tsx'
import { useT } from './i18n/index.tsx'
import { wsClient, type WsMessage } from './api/ws.ts'
import { Layout } from './components/Layout.tsx'
import { Button, Card, Skeleton, Spinner } from './components/ui.tsx'
import { Login } from './pages/Login.tsx'
import { Setup } from './pages/Setup.tsx'
import { Dashboard } from './pages/Dashboard.tsx'
import { Servers } from './pages/Servers.tsx'
import { NotFound } from './pages/NotFound.tsx'

// Route-level code splitting: the heavy surfaces (server detail with terminal +
// editors, creation flows, catalogs, admin) load on demand. Login/Setup/
// Dashboard/Servers stay eager — they are the first-paint and most common
// landing surfaces, and already have their own content-shaped skeletons.
const CreateServer = lazy(() => import('./pages/CreateServer.tsx').then((m) => ({ default: m.CreateServer })))
const ServerDetail = lazy(() => import('./pages/server/ServerDetail.tsx').then((m) => ({ default: m.ServerDetail })))
const Blueprints = lazy(() => import('./pages/Blueprints.tsx').then((m) => ({ default: m.Blueprints })))
const Catalog = lazy(() => import('./pages/Catalog.tsx').then((m) => ({ default: m.Catalog })))
const AdminUsers = lazy(() => import('./pages/AdminUsers.tsx').then((m) => ({ default: m.AdminUsers })))
const NodesPage = lazy(() => import('./pages/NodesPage.tsx').then((m) => ({ default: m.NodesPage })))
const AuditLog = lazy(() => import('./pages/AuditLog.tsx').then((m) => ({ default: m.AuditLog })))
const PanelSettingsPage = lazy(() => import('./pages/PanelSettingsPage.tsx').then((m) => ({ default: m.PanelSettingsPage })))
const Account = lazy(() => import('./pages/Account.tsx').then((m) => ({ default: m.Account })))
const Appearance = lazy(() => import('./pages/Appearance.tsx').then((m) => ({ default: m.Appearance })))

function Splash() {
  return (
    <div className="app-bg flex h-full items-center justify-center">
      <div className="text-center">
        <div className="font-display text-3xl font-bold text-gradient">Between</div>
        <Spinner />
      </div>
    </div>
  )
}

/** Generic glass skeleton shown while a lazy route chunk downloads. The pages
 *  that need them render their own content-shaped skeletons once mounted. */
function PageFallback() {
  return (
    <div aria-busy="true" className="space-y-4">
      <Skeleton className="h-8 w-56 rounded-full" />
      <Skeleton className="h-4 w-80 max-w-full rounded-full" />
      <div className="grid gap-4 sm:grid-cols-2">
        <Skeleton className="h-40 rounded-2xl" />
        <Skeleton className="h-40 rounded-2xl" />
      </div>
      <Skeleton className="h-64 rounded-2xl" />
    </div>
  )
}

/** Shown when a lazy chunk fails to load (e.g. stale chunk names after a
 *  redeploy) — a full reload fetches fresh HTML with the current chunk map. */
function ChunkErrorFallback() {
  const t = useT()
  return (
    <div className="fade-in-up mx-auto max-w-md">
      <Card className="p-8 text-center">
        <div className="font-display text-lg font-bold">{t('chunk.errorTitle')}</div>
        <p className="mt-2 text-[0.8125rem] leading-relaxed text-muted">{t('chunk.errorBody')}</p>
        <Button variant="primary" className="mt-5" onClick={() => window.location.reload()}>
          {t('common.retry')}
        </Button>
      </Card>
    </div>
  )
}

class ChunkErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false }
  static getDerivedStateFromError() {
    return { failed: true }
  }
  render() {
    return this.state.failed ? <ChunkErrorFallback /> : this.props.children
  }
}

/** Per-route boundary: a fresh Suspense per navigation shows the skeleton
 *  immediately (transitions never hide the fallback of a new boundary). */
function LazyPage({ children }: { children: ReactNode }) {
  return (
    <ChunkErrorBoundary>
      <Suspense fallback={<PageFallback />}>{children}</Suspense>
    </ChunkErrorBoundary>
  )
}

/** Global toasts for crash events and WS connection loss. */
function GlobalWsToasts() {
  const toast = useToast()
  const t = useT()
  useEffect(() => {
    let lost = false
    return wsClient.onMessage((msg: WsMessage) => {
      if (msg.t === 'event' && msg.kind === 'crash') {
        const name = typeof msg.name === 'string' ? msg.name : null
        toast('error', name ? t('toast.crash', { name }) : String(msg.message))
      } else if (msg.t === '_close') {
        // Tell the user NOW that live data is frozen — not after the fact.
        lost = true
        toast('error', t('ws.reconnecting'))
      } else if (msg.t === '_open' && lost) {
        toast('success', t('ws.reconnected'))
        lost = false
      }
    })
  }, [toast, t])
  return null
}

export function App() {
  const { user, meta, loading } = useAuth()
  const location = useLocation()

  if (loading) return <Splash />

  if (meta?.setupRequired) {
    return (
      <Routes>
        <Route path="/setup" element={<Setup />} />
        <Route path="*" element={<Navigate to="/setup" replace />} />
      </Routes>
    )
  }

  if (!user) {
    return (
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="*" element={<Navigate to="/login" replace state={{ from: location.pathname }} />} />
      </Routes>
    )
  }

  const isAdmin = user.role === 'admin'
  return (
    <>
      <GlobalWsToasts />
      <Routes>
        <Route element={<Layout />}>
          <Route path="/" element={<Dashboard />} />
          <Route path="/servers" element={<Servers />} />
          <Route path="/servers/new" element={<LazyPage><CreateServer /></LazyPage>} />
          <Route path="/servers/:id/*" element={<LazyPage><ServerDetail /></LazyPage>} />
          <Route path="/blueprints" element={<LazyPage><Blueprints /></LazyPage>} />
          {/* Add actions are admin-gated server-side; browsing is for everyone. */}
          <Route path="/catalog" element={<LazyPage><Catalog /></LazyPage>} />
          <Route path="/account" element={<LazyPage><Account /></LazyPage>} />
          <Route path="/appearance" element={<LazyPage><Appearance /></LazyPage>} />
          {isAdmin && <Route path="/admin/nodes" element={<LazyPage><NodesPage /></LazyPage>} />}
          {isAdmin && <Route path="/admin/users" element={<LazyPage><AdminUsers /></LazyPage>} />}
          {isAdmin && <Route path="/admin/audit" element={<LazyPage><AuditLog /></LazyPage>} />}
          {isAdmin && <Route path="/admin/settings" element={<LazyPage><PanelSettingsPage /></LazyPage>} />}
          {/* Return to the deep link that originally redirected to /login */}
          <Route
            path="/login"
            element={<Navigate to={(location.state as { from?: string } | null)?.from ?? '/'} replace />}
          />
          <Route path="/setup" element={<Navigate to="/" replace />} />
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </>
  )
}
