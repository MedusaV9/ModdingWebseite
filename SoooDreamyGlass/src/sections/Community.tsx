import GradientButton from '../components/GradientButton'
import Marquee from '../components/Marquee'
import useReveal from '../hooks/useReveal'
import { LINKS } from '../data/links'

const credits = [
  { name: 'Sonic0810', role: 'Launcher & core mods' },
  { name: 'jackmygoodman', role: 'Boss Rush mods' },
]

const externalLinks = [
  { label: 'OFFICIAL SITE', href: LINKS.officialSite },
  { label: 'STEAM PAGE', href: LINKS.steam },
  { label: 'WATCH THE TRAILER', href: LINKS.trailer },
]

export default function Community() {
  const reveal = useReveal()

  return (
    <section
      id="community"
      aria-labelledby="community-heading"
      className="bg-bap-night"
    >
      <div
        ref={reveal.ref}
        className={`mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28 ${reveal.className}`}
      >
        {/* Banner */}
        <div className="flex flex-col items-center gap-6 bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] px-6 py-16 text-center md:px-12">
          <h2
            id="community-heading"
            className="font-display uppercase text-4xl text-white md:text-5xl"
          >
            JOIN THE BAPBAP MODDING COMMUNITY
          </h2>
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

        {/* Credits */}
        <div className="mt-14 flex flex-col gap-6">
          <span className="font-teko uppercase text-bap-pink tracking-widest text-lg leading-none">
            CREDITS
          </span>
          <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
            {credits.map((credit) => (
              <div
                key={credit.name}
                className="flex items-center gap-4 border border-bap-line bg-bap-plum p-4"
              >
                <span className="flex h-14 w-14 shrink-0 items-center justify-center bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] font-display text-2xl uppercase text-white">
                  {credit.name.charAt(0)}
                </span>
                <div className="flex flex-col gap-0.5">
                  <span className="font-display uppercase text-sm text-white">
                    {credit.name}
                  </span>
                  <span className="text-white/60 text-sm">{credit.role}</span>
                </div>
              </div>
            ))}
          </div>

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
      </div>

      <Marquee text="READY TO MOD?" />
    </section>
  )
}
