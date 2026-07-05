import { useState } from 'react'
import GradientButton from './GradientButton'
import { LINKS } from '../data/links'

const links = [
  { label: 'Mods', href: '#mods' },
  { label: 'Game Modes', href: '#modes' },
  { label: 'Launcher', href: '#launcher' },
  { label: 'How It Works', href: '#how-it-works' },
  { label: 'Community', href: '#community' },
]

export default function Navbar() {
  const [open, setOpen] = useState(false)

  return (
    <header className="sticky top-0 z-50 bg-bap-plum/80 backdrop-blur border-b border-bap-line">
      <nav
        aria-label="Main navigation"
        className="mx-auto flex max-w-7xl items-center justify-between gap-6 px-4 py-3 md:px-6"
      >
        <a href="#top" className="font-display text-lg uppercase leading-none">
          <span className="text-white">BAPBAP</span>
          <span className="text-bap-pink">·MODS</span>
        </a>

        <ul className="hidden items-center gap-6 md:flex">
          {links.map((link) => (
            <li key={link.href}>
              <a
                href={link.href}
                className="font-teko uppercase text-lg leading-none text-white/80 transition-colors hover:text-bap-pink"
              >
                {link.label}
              </a>
            </li>
          ))}
        </ul>

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
              <li key={link.href}>
                <a
                  href={link.href}
                  onClick={() => setOpen(false)}
                  className="block border-b border-bap-line/50 py-3 font-teko uppercase text-2xl leading-none text-white/80 transition-colors hover:text-bap-pink"
                >
                  {link.label}
                </a>
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
