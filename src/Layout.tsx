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
      {/* Skip link: preventDefault keeps HashRouter from treating "#main" as
          a route — we move focus/scroll to the landmark manually instead. */}
      <a
        href="#main"
        onClick={(event) => {
          event.preventDefault()
          const main = document.getElementById('main')
          main?.focus()
          main?.scrollIntoView()
        }}
        className="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-[60] focus:bg-bap-pink focus:text-white focus:px-4 focus:py-2 font-teko uppercase"
      >
        SKIP TO CONTENT
      </a>
      <ScrollToTop />
      <Navbar onOpenSearch={openPalette} />
      <main id="main" tabIndex={-1}>
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
