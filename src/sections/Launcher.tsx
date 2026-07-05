import GradientButton from '../components/GradientButton'
import SectionHeading from '../components/SectionHeading'
import { LAUNCHER } from '../data/launcher'
import { LINKS } from '../data/links'

export default function Launcher() {
  return (
    <section id="launcher" className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28">
      <div className="grid grid-cols-1 gap-12 lg:grid-cols-2 lg:gap-16">
        <div className="flex flex-col gap-8">
          <SectionHeading eyebrow="BAPBAP NEXUS" title="ONE LAUNCHER. EVERYTHING." />

          <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
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

          <p className="text-white/40 text-sm">
            Windows x64 · Free · Auto-updates · Installs MelonLoader for you
          </p>
        </div>

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
      </div>
    </section>
  )
}
