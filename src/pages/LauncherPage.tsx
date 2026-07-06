import GradientButton from '../components/GradientButton'
import SectionHeading from '../components/SectionHeading'
import usePageMeta from '../hooks/usePageMeta'
import useReveal from '../hooks/useReveal'
import { LAUNCHER } from '../data/launcher'
import { LINKS } from '../data/links'

export default function LauncherPage() {
  usePageMeta(
    'Launcher',
    'Download BAPBAP Nexus v4.0.4 for Windows — one-click mod installs, MelonLoader built in, archived builds and BAPBAP Radio.',
  )

  const revealHeader = useReveal()
  const revealDetails = useReveal()
  const revealChangelog = useReveal()

  return (
    <>
      {/* Header + feature grid */}
      <section
        aria-labelledby="launcher-heading"
        className="mx-auto max-w-7xl px-4 py-20 md:px-6"
      >
        <div
          ref={revealHeader.ref}
          className={`flex flex-col gap-10 ${revealHeader.className}`}
        >
          <div className="flex flex-col gap-6">
            <SectionHeading
              id="launcher-heading"
              eyebrow="BAPBAP NEXUS"
              title="ONE LAUNCHER. EVERYTHING."
              subtitle="Mods, game modes, archived builds and the radio — the whole BAPBAP modding scene runs through one free launcher."
            />
            <p className="font-teko uppercase text-xl leading-none text-white/60">
              v{LAUNCHER.version} · {LAUNCHER.platform} · FREE · AUTO-UPDATES
            </p>
            <div className="flex flex-wrap items-center gap-4">
              <GradientButton
                href={LINKS.launcherDownload}
                target="_blank"
                rel="noreferrer"
              >
                DOWNLOAD FOR WINDOWS (v{LAUNCHER.version})
              </GradientButton>
              <GradientButton
                variant="outline"
                href={LINKS.github}
                target="_blank"
                rel="noreferrer"
              >
                VIEW ON GITHUB
              </GradientButton>
            </div>
          </div>

          <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {LAUNCHER.features.map((feature) => (
              <div key={feature.title} className="flex flex-col gap-1.5">
                <div className="flex items-center gap-2">
                  <span className="h-2.5 w-2.5 shrink-0 bg-bap-pink" />
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

      {/* Requirements + MelonLoader explainer */}
      <section
        aria-label="Requirements and MelonLoader"
        className="border-y border-bap-line bg-bap-plum/30"
      >
        <div
          ref={revealDetails.ref}
          className={`mx-auto grid max-w-7xl grid-cols-1 gap-6 px-4 py-16 md:px-6 lg:grid-cols-2 ${revealDetails.className}`}
        >
          <div className="flex flex-col gap-4 border border-bap-line bg-bap-night p-6 transition duration-150 hover:border-bap-pink md:p-8">
            <h2 className="font-display uppercase text-2xl text-white">
              REQUIREMENTS
            </h2>
            <ul className="flex flex-col gap-2">
              {LAUNCHER.requirements.map((requirement) => (
                <li key={requirement} className="flex items-center gap-2">
                  <span className="h-2.5 w-2.5 shrink-0 bg-bap-pink" />
                  <span className="font-teko uppercase text-lg leading-none text-white/80">
                    {requirement}
                  </span>
                </li>
              ))}
            </ul>
            <div className="mt-auto flex flex-col gap-1 border-t border-bap-line pt-4">
              <span className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                INSTALLER
              </span>
              <span className="break-all text-sm text-white/80">
                {LAUNCHER.installer.fileName}
              </span>
              <span className="break-all text-xs text-white/40">
                SHA-256: {LAUNCHER.installer.sha256}
              </span>
            </div>
          </div>

          <div className="flex flex-col gap-4 border border-bap-line bg-bap-night p-6 transition duration-150 hover:border-bap-pink md:p-8">
            <h2 className="font-display uppercase text-2xl text-white">
              WHAT IS MELONLOADER?
            </h2>
            <p className="text-white/60 text-sm leading-relaxed">
              MelonLoader is the Unity mod loader that BAPBAP mods run on. The
              launcher auto-installs the pinned version{' '}
              <span className="text-white/80">
                {LAUNCHER.melonLoader.version}
              </span>{' '}
              — both x64 and x86 builds are hash-verified from the BAPHub repo.
              Mods themselves are .dll files placed in the game&apos;s Mods/
              folder; the launcher handles all of that for you.
            </p>
            <p className="text-white/60 text-sm">
              {LAUNCHER.melonLoader.note}
            </p>
            <div className="mt-auto pt-2">
              <GradientButton variant="outline" to="/guide">
                READ THE INSTALL GUIDE
              </GradientButton>
            </div>
          </div>
        </div>
      </section>

      {/* Full changelog + cross-links */}
      <section
        aria-labelledby="changelog-heading"
        className="mx-auto max-w-7xl px-4 py-16 pb-20 md:px-6"
      >
        <div
          ref={revealChangelog.ref}
          className={`flex flex-col gap-10 ${revealChangelog.className}`}
        >
          <SectionHeading
            id="changelog-heading"
            eyebrow="EVERY RELEASE"
            title="FULL CHANGELOG"
            subtitle="All 10 stable releases — from the very first Launcher V2 build to today's BAPBAP Nexus."
          />

          <div className="flex flex-col border border-bap-line bg-bap-black">
            <div className="flex items-center justify-between border-b border-bap-line px-5 py-3">
              <span className="font-teko uppercase text-xl leading-none tracking-widest text-white">
                PATCH NOTES
              </span>
              <span className="flex gap-1.5">
                <span className="h-2.5 w-2.5 rounded-full bg-bap-red" />
                <span className="h-2.5 w-2.5 rounded-full bg-bap-amber" />
                <span className="h-2.5 w-2.5 rounded-full bg-bap-pink" />
              </span>
            </div>
            <ul className="flex flex-col divide-y divide-bap-line">
              {LAUNCHER.changelog.map((entry) => (
                <li key={entry.version} className="flex flex-col gap-1 px-5 py-4">
                  <div className="flex items-baseline gap-3">
                    <span className="font-teko uppercase text-xl leading-none text-bap-pink">
                      v{entry.version}
                    </span>
                    <span className="text-white/40 text-sm">{entry.date}</span>
                  </div>
                  <p className="text-white/80 text-sm">{entry.notes}</p>
                </li>
              ))}
            </ul>
          </div>

          <div className="flex flex-wrap items-center justify-center gap-4">
            <GradientButton variant="outline" to="/modes">
              VERSION TIME MACHINE
            </GradientButton>
            <GradientButton variant="outline" to="/radio">
              BAPBAP RADIO SHIPS IN THE LAUNCHER
            </GradientButton>
          </div>
        </div>
      </section>
    </>
  )
}
