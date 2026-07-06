import { lazy } from 'react'
import { HashRouter, Route, Routes } from 'react-router-dom'
import Layout from './Layout'

// Route-level code-splitting: each page becomes its own chunk. Layout stays
// eager so Navbar/Footer render immediately and never unmount.
const Home = lazy(() => import('./pages/Home'))
const ModsPage = lazy(() => import('./pages/ModsPage'))
const ModDetailPage = lazy(() => import('./pages/ModDetailPage'))
const ModesPage = lazy(() => import('./pages/ModesPage'))
const LauncherPage = lazy(() => import('./pages/LauncherPage'))
const RadioPage = lazy(() => import('./pages/RadioPage'))
const GuidePage = lazy(() => import('./pages/GuidePage'))
const ModdersPage = lazy(() => import('./pages/ModdersPage'))
const CommunityPage = lazy(() => import('./pages/CommunityPage'))
const NotFound = lazy(() => import('./pages/NotFound'))

// HashRouter is deliberate: the site is deployed as static files (vite
// preview / static hosting) with no SPA fallback, so BrowserRouter deep
// links would 404 on refresh.
export default function App() {
  return (
    <HashRouter>
      <Routes>
        <Route element={<Layout />}>
          <Route path="/" element={<Home />} />
          <Route path="/mods" element={<ModsPage />} />
          <Route path="/mods/:id" element={<ModDetailPage />} />
          <Route path="/modes" element={<ModesPage />} />
          <Route path="/launcher" element={<LauncherPage />} />
          <Route path="/radio" element={<RadioPage />} />
          <Route path="/guide" element={<GuidePage />} />
          <Route path="/modders" element={<ModdersPage />} />
          <Route path="/community" element={<CommunityPage />} />
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </HashRouter>
  )
}
