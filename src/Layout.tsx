import { Suspense } from 'react'
import { Outlet } from 'react-router-dom'
import Footer from './components/Footer'
import Navbar from './components/Navbar'
import PageLoader from './components/PageLoader'
import ScrollToTop from './components/ScrollToTop'

export default function Layout() {
  return (
    <>
      <ScrollToTop />
      <Navbar />
      <main>
        {/* Suspense lives inside <main> so Navbar/Footer never unmount while
            a lazy route chunk loads. */}
        <Suspense fallback={<PageLoader />}>
          <Outlet />
        </Suspense>
      </main>
      <Footer />
    </>
  )
}
