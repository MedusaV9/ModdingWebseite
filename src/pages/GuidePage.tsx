import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import GradientButton from '../components/GradientButton'
import SectionHeading from '../components/SectionHeading'
import usePageTitle from '../hooks/usePageTitle'
import useReveal from '../hooks/useReveal'
import { LINKS } from '../data/links'

const linkClasses = 'text-bap-pink hover:underline'

const steps: { title: string; text: ReactNode }[] = [
  {
    title: 'Own BAPBAP on Steam',
    text: (
      <>
        The base game comes first — grab{' '}
        <a
          href={LINKS.steam}
          target="_blank"
          rel="noreferrer"
          className={linkClasses}
        >
          BAPBAP on Steam
        </a>{' '}
        (App ID 2226280). The launcher works with your existing Steam install.
      </>
    ),
  },
  {
    title: 'Download BAPBAP Nexus v4.0.4',
    text: (
      <>
        <a
          href={LINKS.launcherDownload}
          target="_blank"
          rel="noreferrer"
          className={linkClasses}
        >
          Download the installer
        </a>{' '}
        (BAPBAP.Nexus.Setup.4.0.4.exe, Windows x64) and run it. Free, with
        auto-updates.
      </>
    ),
  },
  {
    title: 'MelonLoader installs itself',
    text: (
      <>
        The launcher auto-installs MelonLoader{' '}
        <span className="text-white/80">0.7.2-ci.2388</span>, the Unity mod
        loader BAPBAP mods run on. No manual setup, ever.
      </>
    ),
  },
  {
    title: 'Pick your track',
    text: (
      <>
        Latest official build-2025-08-19, an{' '}
        <Link to="/modes" className={linkClasses}>
          archived snapshot
        </Link>{' '}
        back to 2025-04-22, the Boss Rush branch, or the ≈565 MB Battle Royale
        Playtest bundle.
      </>
    ),
  },
  {
    title: 'One-click install mods',
    text: (
      <>
        <Link to="/mods" className={linkClasses}>
          Browse BAPHub
        </Link>{' '}
        and hit install — SHA-256-verified .dll files land in the game&apos;s
        Mods/ folder automatically.
      </>
    ),
  },
  {
    title: 'BAP away',
    text: (
      <>
        Launch the game straight from the launcher. Your modded setup stays
        clean and switchable per track.
      </>
    ),
  },
]

const faqs: { question: string; answer: string }[] = [
  {
    question: 'What is MelonLoader?',
    answer:
      'MelonLoader is the Unity mod loader that BAPBAP mods run on. The launcher pins a known-good version (0.7.2-ci.2388) and manages it automatically — you never install or update it by hand.',
  },
  {
    question: 'Is this safe?',
    answer:
      'The whole mod manifest is open on GitHub, every download is verified against a SHA-256 hash before it touches your install, and downloads are HTTPS-only. Nothing is installed that you can’t inspect.',
  },
  {
    question: 'What does HOST-ONLY mean?',
    answer:
      'Host-only mods only need to be installed by the player hosting the match — everyone else in the lobby gets the effect without installing anything.',
  },
  {
    question: 'Where do mods live?',
    answer:
      'Mods are .dll files in the Mods/ folder inside the game install. The launcher manages them for you per track and per instance, so you never dig through folders yourself.',
  },
  {
    question: 'How do I uninstall?',
    answer:
      'Toggle or remove any mod from the launcher, or switch back to the vanilla track at any time. No manual cleanup needed.',
  },
  {
    question: 'Does this affect the normal game?',
    answer:
      'No — tracks and instances keep your vanilla install clean. Switch back to the unmodded game whenever you want.',
  },
]

export default function GuidePage() {
  usePageTitle('Getting Started')

  const revealSteps = useReveal()
  const revealFaq = useReveal()
  const revealCta = useReveal()

  return (
    <>
      {/* Numbered steps */}
      <section
        aria-labelledby="guide-heading"
        className="mx-auto max-w-7xl px-4 py-20 md:px-6"
      >
        <div ref={revealSteps.ref} className={revealSteps.className}>
          <SectionHeading
            id="guide-heading"
            eyebrow="ZERO FRICTION"
            title="GETTING STARTED"
            subtitle="From vanilla BAPBAP to fully modded in about five minutes."
          />

          <ol className="mt-12 grid grid-cols-1 gap-10 sm:grid-cols-2 lg:grid-cols-3">
            {steps.map((step, index) => (
              <li key={step.title} className="flex flex-col gap-3">
                <span
                  aria-hidden
                  className="font-display text-7xl leading-none text-transparent"
                  style={{ WebkitTextStroke: '2px rgba(255,42,109,0.6)' }}
                >
                  {index + 1}
                </span>
                <h2 className="font-teko uppercase text-2xl leading-none text-white">
                  {step.title}
                </h2>
                <p className="text-white/60 text-sm">{step.text}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* FAQ */}
      <section
        aria-labelledby="faq-heading"
        className="border-y border-bap-line bg-bap-plum/30"
      >
        <div
          ref={revealFaq.ref}
          className={`mx-auto max-w-7xl px-4 py-16 md:px-6 ${revealFaq.className}`}
        >
          <SectionHeading
            id="faq-heading"
            eyebrow="GOOD TO KNOW"
            title="FAQ"
          />

          <div className="mt-10 flex flex-col divide-y divide-bap-line border border-bap-line bg-bap-night">
            {faqs.map((faq) => (
              <details key={faq.question} className="group">
                <summary className="flex cursor-pointer items-center justify-between gap-4 px-5 py-4 font-teko uppercase text-xl leading-none text-white transition-colors hover:text-bap-pink">
                  {faq.question}
                  <span
                    aria-hidden
                    className="shrink-0 text-bap-pink transition-transform duration-200 group-open:rotate-45"
                  >
                    +
                  </span>
                </summary>
                <p className="px-5 pb-5 text-white/60 text-sm leading-relaxed">
                  {faq.answer}
                </p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* CTA band */}
      <section
        aria-label="Next steps"
        className="mx-auto max-w-7xl px-4 py-16 pb-20 md:px-6"
      >
        <div
          ref={revealCta.ref}
          className={`flex flex-col items-center gap-6 border border-bap-line bg-bap-plum px-6 py-12 text-center md:px-12 ${revealCta.className}`}
        >
          <p className="font-display uppercase text-2xl text-white md:text-3xl">
            SET UP? TIME TO PICK YOUR MODS.
          </p>
          <div className="flex flex-wrap items-center justify-center gap-4">
            <GradientButton to="/mods">BROWSE MODS</GradientButton>
            <GradientButton
              variant="outline"
              href={LINKS.discord}
              target="_blank"
              rel="noreferrer"
            >
              ASK ON DISCORD
            </GradientButton>
          </div>
        </div>
      </section>
    </>
  )
}
