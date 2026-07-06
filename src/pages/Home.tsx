import { Link } from 'react-router-dom'
import Badge from '../components/Badge'
import GradientButton from '../components/GradientButton'
import Marquee from '../components/Marquee'
import ModCard from '../components/ModCard'
import ModeArt from '../components/ModeArt'
import SectionHeading from '../components/SectionHeading'
import Icon from '../components/brand/Icon'
import type { IconName } from '../components/brand/Icon'
import Hero from '../sections/Hero'
import HowItWorks from '../sections/HowItWorks'
import usePageMeta from '../hooks/usePageMeta'
import useReveal from '../hooks/useReveal'
import { LAUNCHER } from '../data/launcher'
import { LINKS } from '../data/links'
import { MODES } from '../data/modes'
import { MODS } from '../data/mods'
import type { ModeArtId } from '../components/ModeArt'

const launcherFeatureIcons: IconName[] = ['wrench', 'shield', 'clock']

export default function Home() {
  usePageMeta(
    '',
    'Community mods, custom game modes and the BAPBAP Nexus launcher for BAPBAP — the roguelike party game. Join the modding community on Discord.',
  )

  const revealMods = useReveal({ stagger: true })
  const revealModes = useReveal()
  const revealLauncher = useReveal()
  const revealCommunity = useReveal()

  return (
    <>
      <Hero />

      {/* Featured mods */}
      <section
        aria-labelledby="featured-mods-heading"
        className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28"
      >
        <div ref={revealMods.ref}>
          <div className={revealMods.className}>
            <SectionHeading
              id="featured-mods-heading"
              eyebrow="BAPHUB CATALOG"
              title="FEATURED MODS"
              subtitle="Real community mods, installable in one click through the BAPBAP Nexus launcher."
            />
          </div>

          <div className="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {MODS.slice(0, 6).map((mod, index) => (
              <div
                key={mod.id}
                className={revealMods.className}
                style={revealMods.childStyle(index)}
              >
                <ModCard mod={mod} />
              </div>
            ))}
          </div>

          <div
            className={`mt-12 flex justify-center ${revealMods.className}`}
            style={revealMods.childStyle(5)}
          >
            <GradientButton to="/mods">
              BROWSE ALL {MODS.length} MODS
            </GradientButton>
          </div>
        </div>
      </section>

      {/* Game modes teaser */}
      <section
        aria-labelledby="modes-teaser-heading"
        className="border-y border-bap-line bg-bap-plum/30"
      >
        <div
          ref={revealModes.ref}
          className={`mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28 ${revealModes.className}`}
        >
          <SectionHeading
            id="modes-teaser-heading"
            eyebrow="MORE WAYS TO PLAY"
            title="GAME MODES & TRACKS"
          />

          <div className="mt-12 grid grid-cols-1 gap-6 lg:grid-cols-3">
            {MODES.map((mode) => (
              <article
                key={mode.id}
                className="flex flex-col border border-bap-line bg-bap-night transition duration-150 hover:border-bap-pink"
              >
                <ModeArt mode={mode.id as ModeArtId} className="h-24" />
                <div className="flex flex-1 flex-col gap-4 p-6">
                  <div className="flex flex-col gap-1">
                    <span className="font-teko uppercase text-bap-pink leading-none tracking-widest">
                      {mode.tagline}
                    </span>
                    <h3 className="font-display uppercase text-2xl text-white">
                      {mode.name}
                    </h3>
                  </div>
                  <p className="text-white/70 text-sm leading-relaxed">
                    {mode.description}
                  </p>
                  <div className="mt-auto flex flex-wrap gap-1.5 pt-2">
                    {mode.highlights.map((highlight) => (
                      <Badge key={highlight}>{highlight}</Badge>
                    ))}
                  </div>
                </div>
              </article>
            ))}
          </div>

          <div className="mt-12 flex justify-center">
            <GradientButton to="/modes">EXPLORE GAME MODES</GradientButton>
          </div>
        </div>
      </section>

      {/* Launcher teaser */}
      <section
        aria-labelledby="launcher-teaser-heading"
        className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28"
      >
        <div
          ref={revealLauncher.ref}
          className={`grid grid-cols-1 gap-12 lg:grid-cols-2 lg:gap-16 ${revealLauncher.className}`}
        >
          <div className="flex flex-col gap-8">
            <SectionHeading
              id="launcher-teaser-heading"
              eyebrow="BAPBAP NEXUS"
              title="ONE LAUNCHER. EVERYTHING."
            />

            <div className="flex flex-wrap items-center gap-4">
              <GradientButton to="/launcher">
                LAUNCHER &amp; CHANGELOG
              </GradientButton>
              <GradientButton
                variant="outline"
                href={LINKS.launcherDownload}
                target="_blank"
                rel="noreferrer"
              >
                DOWNLOAD FOR WINDOWS (v{LAUNCHER.version})
              </GradientButton>
            </div>

            <p className="text-white/60 text-sm">
              Windows x64 · Free · Auto-updates · Installs MelonLoader for you
            </p>
          </div>

          <div className="flex flex-col justify-center gap-6">
            {LAUNCHER.features.slice(0, 3).map((feature, index) => (
              <div key={feature.title} className="flex flex-col gap-1.5">
                <div className="flex items-center gap-2">
                  <Icon
                    name={launcherFeatureIcons[index]}
                    className="h-5 w-5 shrink-0 text-bap-pink"
                  />
                  <h3 className="font-teko uppercase text-xl leading-none text-white">
                    {feature.title}
                  </h3>
                </div>
                <p className="text-white/60 text-sm">{feature.text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <HowItWorks />

      {/* Community CTA */}
      <section aria-labelledby="community-cta-heading" className="bg-bap-night">
        <div
          ref={revealCommunity.ref}
          className={`mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28 ${revealCommunity.className}`}
        >
          <Marquee
            variant="solid"
            direction="right"
            speed={26}
            text="JOIN THE DISCORD"
          />
          <div className="flex flex-col items-center gap-6 bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] px-6 py-16 text-center md:px-12">
            <h2
              id="community-cta-heading"
              className="font-display uppercase text-4xl text-white md:text-5xl"
            >
              JOIN THE BAPBAP MODDING COMMUNITY
            </h2>
            <p className="font-teko uppercase text-2xl leading-none text-white/90">
              MOD DROPS ✕ PLAYTESTS ✕ SPEEDRUNS ✕ DEV TALK
            </p>
            <div className="flex flex-wrap items-center justify-center gap-4">
              <Link
                to="/community"
                className="inline-block bg-white text-bap-red font-teko font-bold text-[1.2rem] uppercase leading-none tracking-wide pt-[13px] px-5 pb-2 transition duration-100 hover:brightness-90 hover:-translate-y-0.5 cursor-pointer select-none"
              >
                MEET THE COMMUNITY
              </Link>
              <a
                href={LINKS.discord}
                target="_blank"
                rel="noreferrer"
                className="inline-block border-2 border-white text-white font-teko font-bold text-[1.2rem] uppercase leading-none tracking-wide pt-[11px] px-5 pb-1.5 transition duration-100 hover:bg-white hover:text-bap-red hover:-translate-y-0.5 cursor-pointer select-none"
              >
                DISCORD.GG/BAPBAPMODS
              </a>
            </div>
          </div>
        </div>
      </section>
    </>
  )
}
