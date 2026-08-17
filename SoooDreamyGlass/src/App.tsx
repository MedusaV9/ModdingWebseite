import { HashRouter, Route, Routes } from 'react-router-dom'
import Layout from './Layout'
import Home from './pages/Home'
import ModsPage from './pages/ModsPage'
import ModDetailPage from './pages/ModDetailPage'
import ModesPage from './pages/ModesPage'
import LauncherPage from './pages/LauncherPage'
import RadioPage from './pages/RadioPage'
import GuidePage from './pages/GuidePage'
import ModdersPage from './pages/ModdersPage'
import CommunityPage from './pages/CommunityPage'
import NotFound from './pages/NotFound'

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
