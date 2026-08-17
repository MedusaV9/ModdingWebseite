import { useEffect } from 'react'
import { useLocation } from 'react-router-dom'

/**
 * Scrolls the window back to the top whenever the route pathname changes.
 * Uses an instant jump (no smooth scrolling) so it behaves the same with
 * prefers-reduced-motion enabled.
 */
export default function ScrollToTop() {
  const { pathname } = useLocation()

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [pathname])

  return null
}
