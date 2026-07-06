import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { Link, NavLink, useLocation } from 'react-router-dom'
import BrandMark from './brand/BrandMark'
import Emblem from './brand/Emblem'
import Icon from './brand/Icon'
import GradientButton from './GradientButton'
import { LINKS } from '../data/links'

const links = [
  { label: 'Mods', to: '/mods' },
  { label: 'Modes', to: '/modes' },
  { label: 'Launcher', to: '/launcher' },
  { label: 'Radio', to: '/radio' },
  { label: 'Guide', to: '/guide' },
  { label: 'Modders', to: '/modders' },
  { label: 'Community', to: '/community' },
]

const FOCUSABLE_SELECTOR =
  'a[href], button:not([disabled]), input, select, textarea, [tabindex]:not([tabindex="-1"])'

const prefersReducedMotion = () =>
  window.matchMedia('(prefers-reduced-motion: reduce)').matches

export default function Navbar({ onOpenSearch }: { onOpenSearch: () => void }) {
  const [open, setOpen] = useState(false)
  // entered drives the staggered slide-in; instant zeroes the per-link delays
  // (the global reduced-motion CSS kills durations but not transition-delay).
  const [entered, setEntered] = useState(false)
  const [instant, setInstant] = useState(false)

  const headerRef = useRef<HTMLElement>(null)
  const overlayRef = useRef<HTMLDivElement>(null)
  const burgerRef = useRef<HTMLButtonElement>(null)
  const location = useLocation()

  // Close the overlay on route change (also restores body scroll below).
  useEffect(() => {
    setOpen(false)
  }, [location.pathname])

  // Close if the viewport crosses into the desktop breakpoint while open.
  useEffect(() => {
    if (!open) return
    const desktop = window.matchMedia('(min-width: 768px)')
    const onChange = () => {
      if (desktop.matches) setOpen(false)
    }
    desktop.addEventListener('change', onChange)
    return () => desktop.removeEventListener('change', onChange)
  }, [open])

  // Body scroll lock while the overlay is open.
  useEffect(() => {
    if (!open) return
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = ''
    }
  }, [open])

  // Staggered entrance. useLayoutEffect so reduced-motion shows the links
  // before first paint (no hidden flash).
  useLayoutEffect(() => {
    if (!open) {
      setEntered(false)
      setInstant(false)
      return
    }
    if (prefersReducedMotion()) {
      setInstant(true)
      setEntered(true)
      return
    }
    const raf = requestAnimationFrame(() => setEntered(true))
    return () => cancelAnimationFrame(raf)
  }, [open])

  // Focus management: move into the overlay on open, back to the burger on close.
  useEffect(() => {
    if (!open) return
    overlayRef.current?.querySelector<HTMLElement>('a[href]')?.focus()
    const burger = burgerRef.current
    return () => burger?.focus()
  }, [open])

  // Escape closes; Tab is trapped inside the header (persistent row + overlay).
  useEffect(() => {
    if (!open) return
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault()
        setOpen(false)
        return
      }
      // The palette hotkeys ("/" or Ctrl/Cmd+K) open the palette on top of the
      // overlay — close the overlay so the two never fight over the scroll lock.
      const isSlash =
        event.key === '/' && !event.ctrlKey && !event.metaKey && !event.altKey
      const isCtrlK =
        (event.key === 'k' || event.key === 'K') &&
        (event.ctrlKey || event.metaKey)
      if (isSlash || isCtrlK) {
        setOpen(false)
        return
      }
      if (event.key !== 'Tab') return
      const root = headerRef.current
      if (!root) return
      const focusables = Array.from(
        root.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR),
      ).filter((el) => el.getClientRects().length > 0)
      if (focusables.length === 0) return
      const first = focusables[0]
      const last = focusables[focusables.length - 1]
      const active = document.activeElement
      if (event.shiftKey && (active === first || !root.contains(active))) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && (active === last || !root.contains(active))) {
        event.preventDefault()
        first.focus()
      }
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [open])

  const linkEnter = (index: number) => ({
    className: `transition-[opacity,translate] duration-300 ease-out ${
      entered ? 'translate-x-0 opacity-100' : '-translate-x-8 opacity-0'
    }`,
    style: { transitionDelay: instant ? '0ms' : `${index * 60}ms` },
  })

  return (
    <header ref={headerRef} className="sticky top-0 z-50">
      {/* Fullscreen mobile overlay — rendered before the nav row so the
          persistent header row (same z-index, later in the DOM) paints on top. */}
      {open && (
        <div
          id="mobile-menu"
          ref={overlayRef}
          className="fixed inset-0 z-50 flex flex-col overflow-y-auto bg-bap-night/98 md:hidden"
        >
          <div
            aria-hidden
            className="pointer-events-none absolute -bottom-14 -right-14"
          >
            <Emblem className="h-72 w-72 opacity-10" />
          </div>

          <nav
            aria-label="Mobile navigation"
            className="relative flex min-h-full flex-1 flex-col px-6 pt-24 pb-10"
          >
            <ul className="flex flex-col gap-6">
              {links.map((link, index) => (
                <li key={link.to} {...linkEnter(index)}>
                  <NavLink
                    to={link.to}
                    onClick={() => setOpen(false)}
                    className={({ isActive }) =>
                      `inline-block font-teko uppercase text-4xl leading-none transition-colors ${
                        isActive
                          ? 'text-bap-pink'
                          : 'text-white/90 hover:text-bap-pink'
                      }`
                    }
                  >
                    {link.label}
                  </NavLink>
                </li>
              ))}
            </ul>

            <div className={`mt-auto pt-10 ${linkEnter(links.length).className}`} style={linkEnter(links.length).style}>
              <GradientButton
                href={LINKS.discord}
                target="_blank"
                rel="noreferrer"
                onClick={() => setOpen(false)}
                className="shadow-hard"
              >
                Join Discord
              </GradientButton>
            </div>
          </nav>
        </div>
      )}

      {/* Persistent header row. The blur lives here (not on <header>) because
          backdrop-filter would turn the header into the containing block for
          the fixed overlay above. */}
      <div className="relative z-50 border-b border-bap-line bg-bap-plum/80 backdrop-blur">
        <nav
          aria-label="Main navigation"
          className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-3 md:px-6 lg:gap-6"
        >
          <Link to="/" className="inline-flex">
            <BrandMark />
          </Link>

          <ul className="hidden items-center gap-4 md:flex lg:gap-6">
            {links.map((link) => (
              <li key={link.to}>
                <NavLink
                  to={link.to}
                  className={({ isActive }) =>
                    `font-teko uppercase text-lg leading-none transition-colors ${
                      isActive
                        ? 'text-bap-pink'
                        : 'text-white/80 hover:text-bap-pink'
                    }`
                  }
                >
                  {link.label}
                </NavLink>
              </li>
            ))}
          </ul>

          <button
            type="button"
            onClick={() => {
              setOpen(false)
              onOpenSearch()
            }}
            aria-label="Search (press /)"
            className="flex h-10 items-center gap-2 border border-bap-line px-2.5 text-white/60 transition-colors hover:border-bap-pink hover:text-bap-pink cursor-pointer"
          >
            <Icon name="search" className="h-4 w-4" />
            <kbd className="hidden font-teko text-lg leading-none pt-[3px] md:block">
              /
            </kbd>
          </button>

          {/* lg (not md): at exactly 768px the row with 7 links + search + CTA
              is wider than the viewport and causes horizontal overflow. */}
          <div className="hidden lg:block">
            <GradientButton
              href={LINKS.discord}
              target="_blank"
              rel="noreferrer"
              className="text-[1rem] pt-[10px] px-4 pb-1.5"
            >
              Join Discord
            </GradientButton>
          </div>

          <button
            ref={burgerRef}
            type="button"
            onClick={() => setOpen((value) => !value)}
            aria-label={open ? 'Close navigation menu' : 'Open navigation menu'}
            aria-expanded={open}
            aria-controls="mobile-menu"
            className="flex h-10 w-10 flex-col items-center justify-center gap-[5px] border border-bap-line text-white transition-colors hover:border-bap-pink md:hidden"
          >
            <span
              className={`h-0.5 w-5 bg-current transition-transform duration-200 ${
                open ? 'translate-y-[7px] rotate-45' : ''
              }`}
            />
            <span
              className={`h-0.5 w-5 bg-current transition-opacity duration-200 ${
                open ? 'opacity-0' : ''
              }`}
            />
            <span
              className={`h-0.5 w-5 bg-current transition-transform duration-200 ${
                open ? '-translate-y-[7px] -rotate-45' : ''
              }`}
            />
          </button>
        </nav>
      </div>
    </header>
  )
}
