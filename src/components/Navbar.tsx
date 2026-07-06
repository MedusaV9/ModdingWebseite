import { useState } from 'react'
import { Link, NavLink } from 'react-router-dom'
import BrandMark from './brand/BrandMark'
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

export default function Navbar({ onOpenSearch }: { onOpenSearch: () => void }) {
  const [open, setOpen] = useState(false)

  return (
    <header className="sticky top-0 z-50 bg-bap-plum/80 backdrop-blur border-b border-bap-line">
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
          onClick={onOpenSearch}
          aria-label="Search (press /)"
          className="flex h-10 items-center gap-2 border border-bap-line px-2.5 text-white/60 transition-colors hover:border-bap-pink hover:text-bap-pink cursor-pointer"
        >
          <Icon name="search" className="h-4 w-4" />
          <kbd className="hidden font-teko text-lg leading-none pt-[3px] md:block">
            /
          </kbd>
        </button>

        <div className="hidden md:block">
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

      {open && (
        <div
          id="mobile-menu"
          className="w-full border-t border-bap-line bg-bap-plum md:hidden"
        >
          <ul className="flex flex-col px-4 py-2">
            {links.map((link) => (
              <li key={link.to}>
                <NavLink
                  to={link.to}
                  onClick={() => setOpen(false)}
                  className={({ isActive }) =>
                    `block border-b border-bap-line/50 py-3 font-teko uppercase text-2xl leading-none transition-colors ${
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
            <li>
              <a
                href={LINKS.discord}
                target="_blank"
                rel="noreferrer"
                onClick={() => setOpen(false)}
                className="block py-3 font-teko uppercase text-2xl leading-none text-bap-pink transition-colors hover:text-white"
              >
                Join Discord
              </a>
            </li>
          </ul>
        </div>
      )}
    </header>
  )
}
