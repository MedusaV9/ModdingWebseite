import { Suspense, useCallback, useState } from 'react'
import { Outlet } from 'react-router-dom'
import CommandPalette from './components/CommandPalette'
import Footer from './components/Footer'
import Navbar from './components/Navbar'
import PageLoader from './components/PageLoader'
import ScrollToTop from './components/ScrollToTop'

export default function Layout() {
  const [paletteOpen, setPaletteOpen] = useState(false)
  const openPalette = useCallback(() => setPaletteOpen(true), [])
  const closePalette = useCallback(() => setPaletteOpen(false), [])

  return (
    <>
      <ScrollToTop />
      <Navbar onOpenSearch={openPalette} />
      <main>
        {/* Suspense lives inside <main> so Navbar/Footer never unmount while
            a lazy route chunk loads. */}
        <Suspense fallback={<PageLoader />}>
          <Outlet />
        </Suspense>
      </main>
      <Footer />
      <CommandPalette
        open={paletteOpen}
        onOpen={openPalette}
        onClose={closePalette}
      />
    </>
  )
}
