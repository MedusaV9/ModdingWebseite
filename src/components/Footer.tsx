const footerLinks = [
  { label: 'Discord', href: 'https://discord.gg/BAPBAPMods' },
  { label: 'GitHub', href: 'https://github.com/Sonic0810/bapbaplauncher' },
  { label: 'Official site', href: 'https://bapbap.gg' },
  {
    label: 'BAPBAP on Steam',
    href: 'https://store.steampowered.com/app/2226280/BAP_BAP/',
  },
]

export default function Footer() {
  return (
    <footer className="border-t border-bap-line bg-bap-black">
      <div className="mx-auto grid max-w-7xl grid-cols-1 gap-10 px-4 py-12 md:grid-cols-3 md:px-6">
        <div className="flex flex-col gap-3">
          <span className="font-display text-lg uppercase leading-none">
            <span className="text-white">BAPBAP</span>
            <span className="text-bap-pink">·MODS</span>
          </span>
          <p className="text-white/60 text-sm">
            A fan-made modding community for BAPBAP, the roguelike party game.
          </p>
        </div>

        <div className="flex flex-col gap-2">
          <span className="font-teko uppercase tracking-widest text-bap-pink text-lg leading-none">
            Links
          </span>
          <ul className="flex flex-col gap-1">
            {footerLinks.map((link) => (
              <li key={link.href}>
                <a
                  href={link.href}
                  target="_blank"
                  rel="noreferrer"
                  className="text-white/80 transition-colors hover:text-bap-pink"
                >
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        </div>

        <p className="text-white/60 text-sm">
          BAPBAP Modding is a community project and is not affiliated with or
          endorsed by BAPBAP HQ. BAPBAP and all related assets are property of
          their respective owners.
        </p>
      </div>

      <div className="border-t border-bap-line">
        <p className="mx-auto max-w-7xl px-4 py-4 text-center text-white/60 text-sm md:px-6">
          Built by the BAPBAP modding community
        </p>
      </div>
    </footer>
  )
}
