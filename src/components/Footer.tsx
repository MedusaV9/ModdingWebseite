import { Link } from 'react-router-dom'
import BrandMark from './brand/BrandMark'
import Marquee from './Marquee'
import { useI18n } from '../i18n/context'
import type { Dict } from '../i18n/context'

// Route paths / hrefs stay module-scope; labels come from the active dict.
const siteRoutes = [
  { key: 'mods', to: '/mods' },
  { key: 'modes', to: '/modes' },
  { key: 'launcher', to: '/launcher' },
  { key: 'radio', to: '/radio' },
  { key: 'guide', to: '/guide' },
  { key: 'modders', to: '/modders' },
  { key: 'community', to: '/community' },
] as const

const externalRoutes = [
  { key: 'discord', href: 'https://discord.gg/BAPBAPMods' },
  { key: 'github', href: 'https://github.com/Sonic0810/bapbaplauncher' },
  { key: 'official', href: 'https://bapbap.gg' },
  {
    key: 'steam',
    href: 'https://store.steampowered.com/app/2226280/BAP_BAP/',
  },
] as const satisfies readonly { key: keyof Dict['footer']['links']; href: string }[]

export default function Footer() {
  const { t } = useI18n()

  return (
    <>
      <Marquee variant="outline" speed={34} text="BAPBAP MODDING" />
      <footer className="border-t border-bap-line bg-bap-black">
        <div className="mx-auto grid max-w-7xl grid-cols-1 gap-10 px-4 py-12 sm:grid-cols-2 md:px-6 lg:grid-cols-4">
          <div className="flex flex-col gap-3">
            <BrandMark />
            <p className="text-white/60 text-sm">{t.footer.tagline}</p>
            <p className="text-white/50 text-sm">
              {t.footer.quickKeys}{' '}
              <kbd className="border border-bap-line bg-bap-plum px-1.5 py-0.5 font-teko text-white/70">
                /
              </kbd>{' '}
              {t.footer.quickKeysSearch}
            </p>
            {/* white/50 (not /40) — keeps the new line at ≥4.5:1 AA contrast. */}
            <p className="text-white/50 text-sm">{t.footer.pwaNote}</p>
          </div>

          <div className="flex flex-col gap-2">
            <span className="font-teko uppercase tracking-widest text-bap-pink text-lg leading-none">
              {t.footer.siteHeading}
            </span>
            <ul className="flex flex-col gap-1">
              {siteRoutes.map((link) => (
                <li key={link.to}>
                  <Link
                    to={link.to}
                    className="text-white/80 transition-colors hover:text-bap-pink"
                  >
                    {t.nav[link.key]}
                  </Link>
                </li>
              ))}
            </ul>
          </div>

          <div className="flex flex-col gap-2">
            <span className="font-teko uppercase tracking-widest text-bap-pink text-lg leading-none">
              {t.footer.linksHeading}
            </span>
            <ul className="flex flex-col gap-1">
              {externalRoutes.map((link) => (
                <li key={link.href}>
                  <a
                    href={link.href}
                    target="_blank"
                    rel="noreferrer"
                    className="text-white/80 transition-colors hover:text-bap-pink"
                  >
                    {t.footer.links[link.key]}
                  </a>
                </li>
              ))}
            </ul>
          </div>

          <p className="text-white/60 text-sm">{t.footer.disclaimer}</p>
        </div>

        <div className="border-t border-bap-line">
          <p className="mx-auto max-w-7xl px-4 py-4 text-center text-white/60 text-sm md:px-6">
            {t.footer.builtBy}
          </p>
        </div>
      </footer>
    </>
  )
}
