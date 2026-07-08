import { Link } from 'react-router-dom'
import GradientButton from '../components/GradientButton'
import SectionHeading from '../components/SectionHeading'
import usePageMeta from '../hooks/usePageMeta'
import useReveal from '../hooks/useReveal'
import { useI18n } from '../i18n/context'
import { LINKS } from '../data/links'
import { AUTHORS } from '../lib/authors'

const TRAILER_THUMB = 'https://img.youtube.com/vi/Y4p8UyaPmDM/0.jpg'

// Names/urls stay module-scope; role labels come from the active dict
// (t.community.credits.roles) in-component.
const credits: {
  name: string
  roleKey: 'launcher' | 'bossRush'
  url?: string
}[] = [
  {
    name: 'Sonic0810',
    roleKey: 'launcher',
    url: 'https://github.com/Sonic0810',
  },
  { name: 'jackmygoodman', roleKey: 'bossRush' },
]

const externalLinks = [
  { key: 'official', href: LINKS.officialSite },
  { key: 'steam', href: LINKS.steam },
  { key: 'github', href: LINKS.github },
] as const

export default function CommunityPage() {
  const { t } = useI18n()
  usePageMeta(t.meta.community.title, t.meta.community.description)

  const revealBanner = useReveal()
  const revealTrailer = useReveal()
  const revealCredits = useReveal()

  return (
    <>
      {/* Discord banner */}
      <section
        aria-labelledby="community-heading"
        className="mx-auto max-w-7xl px-4 pt-20 md:px-6 md:pt-28"
      >
        <div ref={revealBanner.ref} className={revealBanner.className}>
          <div className="flex flex-col items-center gap-6 bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] px-6 py-16 text-center md:px-12">
            <h1
              id="community-heading"
              className="font-display uppercase text-4xl text-white md:text-5xl"
            >
              {t.community.title}
            </h1>
            <p className="font-teko uppercase text-2xl leading-none text-white/90">
              {t.community.sub}
            </p>
            <a
              href={LINKS.discord}
              target="_blank"
              rel="noreferrer"
              className="inline-block bg-white text-bap-red font-teko font-bold text-[1.2rem] uppercase leading-none tracking-wide pt-[13px] px-5 pb-2 transition duration-100 hover:brightness-90 hover:-translate-y-0.5 cursor-pointer select-none"
            >
              {t.community.discordCta}
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
              eyebrow={t.community.trailer.eyebrow}
              title={t.community.trailer.title}
              subtitle={t.community.trailer.subtitle}
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
                  {t.community.trailer.links[link.key]}
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
              alt={t.community.trailer.thumbAlt}
              loading="lazy"
              onError={(event) => {
                event.currentTarget.style.display = 'none'
              }}
              className="h-full w-full object-cover opacity-80 transition duration-150 group-hover:opacity-100"
            />
            <span className="absolute inset-0 flex items-center justify-center">
              <span className="bg-bap-black/70 px-5 pt-[13px] pb-2 font-teko font-bold uppercase text-2xl leading-none tracking-wide text-white transition duration-150 group-hover:bg-[linear-gradient(to_left,#eb204f,#ff2a6d)]">
                {t.community.trailer.watch}
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
            eyebrow={t.community.credits.eyebrow}
            title={t.community.credits.title}
          />

          <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
            {credits.map((credit) => {
              const modCount =
                AUTHORS.find((entry) => entry.name === credit.name)
                  ?.modCount ?? 0
              return (
                <div
                  key={credit.name}
                  className="flex flex-col gap-4 border border-bap-line bg-bap-plum p-4 transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)]"
                >
                  <div className="flex items-center gap-4">
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
                      <span className="text-white/60 text-sm">
                        {t.community.credits.roles[credit.roleKey]}
                      </span>
                      <span className="font-teko uppercase text-lg leading-none tracking-wide text-bap-pink">
                        {t.community.modCount(modCount)}
                      </span>
                    </div>
                  </div>
                  <GradientButton
                    variant="outline"
                    to={`/mods?author=${encodeURIComponent(credit.name)}`}
                    className="self-start"
                  >
                    {t.community.allTheirMods}
                  </GradientButton>
                </div>
              )
            })}
          </div>

          <p className="text-white/60 text-sm">
            {t.community.credits.welcomeBefore}
            <Link to="/modders" className="text-bap-pink hover:underline">
              {t.community.credits.welcomeLink}
            </Link>
            {t.community.credits.welcomeAfter}
          </p>

          <p className="border border-bap-line bg-bap-night p-4 text-white/60 text-sm">
            {t.community.credits.disclaimer}
          </p>
        </div>
      </section>
    </>
  )
}
