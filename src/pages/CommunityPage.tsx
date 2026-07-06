import { Link } from 'react-router-dom'
import GradientButton from '../components/GradientButton'
import Marquee from '../components/Marquee'
import SectionHeading from '../components/SectionHeading'
import usePageMeta from '../hooks/usePageMeta'
import useReveal from '../hooks/useReveal'
import { LINKS } from '../data/links'

const TRAILER_THUMB = 'https://img.youtube.com/vi/Y4p8UyaPmDM/0.jpg'

const credits: { name: string; role: string; url?: string }[] = [
  {
    name: 'Sonic0810',
    role: 'Launcher & core mods',
    url: 'https://github.com/Sonic0810',
  },
  { name: 'jackmygoodman', role: 'Boss Rush mods' },
]

const externalLinks = [
  { label: 'OFFICIAL SITE', href: LINKS.officialSite },
  { label: 'STEAM PAGE', href: LINKS.steam },
  { label: 'GITHUB / BAPHUB SOURCE', href: LINKS.github },
]

export default function CommunityPage() {
  usePageMeta(
    'Community',
    'Join the BAPBAP modding community on Discord — mod drops, playtests, speedruns and dev talk.',
  )

  const revealBanner = useReveal()
  const revealTrailer = useReveal()
  const revealCredits = useReveal()

  return (
    <>
      {/* Discord banner */}
      <section
        aria-labelledby="community-heading"
        className="mx-auto max-w-7xl px-4 pt-20 md:px-6"
      >
        <div ref={revealBanner.ref} className={revealBanner.className}>
          <div className="flex flex-col items-center gap-6 bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] px-6 py-16 text-center md:px-12">
            <h1
              id="community-heading"
              className="font-display uppercase text-4xl text-white md:text-5xl"
            >
              JOIN THE BAPBAP MODDING COMMUNITY
            </h1>
            <p className="font-teko uppercase text-2xl leading-none text-white/90">
              MOD DROPS ✕ PLAYTESTS ✕ SPEEDRUNS ✕ DEV TALK
            </p>
            <a
              href={LINKS.discord}
              target="_blank"
              rel="noreferrer"
              className="inline-block bg-white text-bap-red font-teko font-bold text-[1.2rem] uppercase leading-none tracking-wide pt-[13px] px-5 pb-2 transition duration-100 hover:brightness-90 hover:-translate-y-0.5 cursor-pointer select-none"
            >
              DISCORD.GG/BAPBAPMODS
            </a>
          </div>
        </div>
      </section>

      {/* Trailer + links */}
      <section
        aria-labelledby="trailer-heading"
        className="mx-auto max-w-7xl px-4 py-16 md:px-6"
      >
        <div
          ref={revealTrailer.ref}
          className={`grid grid-cols-1 gap-10 lg:grid-cols-2 lg:gap-16 ${revealTrailer.className}`}
        >
          <div className="flex flex-col gap-6">
            <SectionHeading
              id="trailer-heading"
              eyebrow="SEE IT IN MOTION"
              title="THE GAME"
              subtitle="BAPBAP is a free-to-play roguelike party brawler on Steam — watch the trailer, then mod it."
            />
            <div className="flex flex-wrap gap-4">
              {externalLinks.map((link) => (
                <GradientButton
                  key={link.href}
                  variant="outline"
                  href={link.href}
                  target="_blank"
                  rel="noreferrer"
                >
                  {link.label}
                </GradientButton>
              ))}
            </div>
          </div>

          <a
            href={LINKS.trailer}
            target="_blank"
            rel="noreferrer"
            className="group relative block aspect-video overflow-hidden border border-bap-line bg-bap-black transition duration-150 hover:border-bap-pink"
          >
            <img
              src={TRAILER_THUMB}
              alt="BAPBAP trailer"
              loading="lazy"
              onError={(event) => {
                event.currentTarget.style.display = 'none'
              }}
              className="h-full w-full object-cover opacity-80 transition duration-150 group-hover:opacity-100"
            />
            <span className="absolute inset-0 flex items-center justify-center">
              <span className="bg-bap-black/70 px-5 pt-[13px] pb-2 font-teko font-bold uppercase text-2xl leading-none tracking-wide text-white transition duration-150 group-hover:bg-[linear-gradient(to_left,#eb204f,#ff2a6d)]">
                WATCH THE TRAILER ▶
              </span>
            </span>
          </a>
        </div>
      </section>

      {/* Credits + disclaimer */}
      <section
        aria-labelledby="credits-heading"
        className="border-t border-bap-line bg-bap-plum/30"
      >
        <div
          ref={revealCredits.ref}
          className={`mx-auto flex max-w-7xl flex-col gap-6 px-4 py-16 md:px-6 ${revealCredits.className}`}
        >
          <SectionHeading
            id="credits-heading"
            eyebrow="THE PEOPLE"
            title="CREDITS"
          />

          <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
            {credits.map((credit) => (
              <div
                key={credit.name}
                className="flex items-center gap-4 border border-bap-line bg-bap-plum p-4 transition duration-150 hover:border-bap-pink"
              >
                <span className="flex h-14 w-14 shrink-0 items-center justify-center bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] font-display text-2xl uppercase text-white">
                  {credit.name.charAt(0)}
                </span>
                <div className="flex flex-col gap-0.5">
                  {credit.url ? (
                    <a
                      href={credit.url}
                      target="_blank"
                      rel="noreferrer"
                      className="font-display uppercase text-sm text-white hover:text-bap-pink transition-colors"
                    >
                      {credit.name}
                    </a>
                  ) : (
                    <span className="font-display uppercase text-sm text-white">
                      {credit.name}
                    </span>
                  )}
                  <span className="text-white/60 text-sm">{credit.role}</span>
                </div>
              </div>
            ))}
          </div>

          <p className="text-white/60 text-sm">
            Building something of your own? New modders are always welcome —{' '}
            <Link to="/modders" className="text-bap-pink hover:underline">
              publish your first mod on BAPHub
            </Link>
            .
          </p>

          <p className="border border-bap-line bg-bap-night p-4 text-white/60 text-sm">
            BAPBAP Modding is a community project and is not affiliated with or
            endorsed by BAPBAP HQ. BAPBAP and all related assets are property
            of their respective owners.
          </p>
        </div>
      </section>

      <Marquee text="READY TO MOD?" />
    </>
  )
}
