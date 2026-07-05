import GradientButton from './GradientButton'

const links = [
  { label: 'Mods', href: '#mods' },
  { label: 'Game Modes', href: '#modes' },
  { label: 'Launcher', href: '#launcher' },
  { label: 'How It Works', href: '#how-it-works' },
  { label: 'Community', href: '#community' },
]

export default function Navbar() {
  return (
    <header className="sticky top-0 z-50 bg-bap-plum/80 backdrop-blur border-b border-bap-line">
      <nav className="mx-auto flex max-w-7xl items-center justify-between gap-6 px-4 py-3 md:px-6">
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

        <GradientButton
          href="https://discord.gg/BAPBAPMods"
          target="_blank"
          rel="noreferrer"
          className="text-[1rem] pt-[10px] px-4 pb-1.5"
        >
          Join Discord
        </GradientButton>
      </nav>
    </header>
  )
}
