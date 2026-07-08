import { Link } from 'react-router-dom'
import Badge from '../components/Badge'
import GradientButton from '../components/GradientButton'
import ModeArt from '../components/ModeArt'
import SectionHeading from '../components/SectionHeading'
import usePageMeta from '../hooks/usePageMeta'
import useReveal from '../hooks/useReveal'
import { useI18n } from '../i18n/context'
import { BUNDLES } from '../data/bundles'
import { MODES } from '../data/modes'
import { MODS } from '../data/mods'
import { VERSIONS } from '../data/versions'
import type { ModeArtId } from '../components/ModeArt'

const bossRushBuild = VERSIONS.builds.find((build) => build.id === 'boss-rush')
const bossRushMods = MODS.filter((mod) => mod.track === 'boss-rush')
const brBundle = BUNDLES[0]
const BR_UI_MOD_ID = 'sonic.bapbap.br-ui-old-but-gold'

function formatDate(utc: string) {
  return utc.slice(0, 10)
}

export default function ModesPage() {
  const { t } = useI18n()
  usePageMeta(t.meta.modes.title, t.meta.modes.description)

  const revealModes = useReveal()
  const revealBossRush = useReveal()
  const revealBundle = useReveal()
  const revealVersions = useReveal()

  return (
    <>
      {/* Mode cards */}
      <section
        aria-labelledby="modes-heading"
        className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28"
      >
        <div ref={revealModes.ref} className={revealModes.className}>
          <SectionHeading
            id="modes-heading"
            eyebrow={t.modes.eyebrow}
            title={t.modes.title}
            subtitle={t.modes.subtitle}
          />

          <div className="mt-12 grid grid-cols-1 gap-6 lg:grid-cols-3">
            {MODES.map((mode) => {
              const card = t.modes.cards[mode.id as ModeArtId]
              return (
                <article
                  key={mode.id}
                  className="flex flex-col border border-bap-line bg-bap-night transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)]"
                >
                  <ModeArt mode={mode.id as ModeArtId} className="h-24" />
                  <div className="flex flex-1 flex-col gap-4 p-6">
                    <div className="flex flex-col gap-1">
                      <span className="font-teko uppercase text-bap-pink leading-none tracking-widest">
                        {card.tagline}
                      </span>
                      <h3 className="font-display uppercase text-2xl text-white">
                        {mode.name}
                      </h3>
                    </div>
                    <p className="text-white/70 text-sm leading-relaxed">
                      {card.description}
                    </p>
                    <div className="mt-auto flex flex-wrap gap-1.5 pt-2">
                      {card.highlights.map((highlight) => (
                        <Badge key={highlight}>{highlight}</Badge>
                      ))}
                    </div>
                  </div>
                </article>
              )
            })}
          </div>
        </div>
      </section>

      {/* Boss Rush deep dive */}
      <section
        aria-labelledby="boss-rush-heading"
        className="border-y border-bap-line bg-bap-plum/30"
      >
        <div
          ref={revealBossRush.ref}
          className={`mx-auto max-w-7xl px-4 py-16 md:px-6 ${revealBossRush.className}`}
        >
          <div className="grid grid-cols-1 gap-10 lg:grid-cols-2 lg:gap-16">
            <div className="flex flex-col gap-6">
              <SectionHeading
                id="boss-rush-heading"
                eyebrow={t.modes.bossRush.eyebrow}
                title={t.modes.bossRush.title}
                subtitle={t.modes.bossRush.subtitle}
              />
              <dl className="flex flex-col gap-3 border border-bap-line bg-bap-night p-6 text-sm">
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <dt className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                    {t.modes.bossRush.branchSnapshot}
                  </dt>
                  <dd className="font-teko uppercase text-lg leading-none text-white">
                    {bossRushBuild ? formatDate(bossRushBuild.releaseDateUtc) : ''}
                  </dd>
                </div>
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <dt className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                    {t.modes.bossRush.steamManifest}
                  </dt>
                  <dd className="break-all text-white/40">
                    {bossRushBuild?.steamManifestId}
                  </dd>
                </div>
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <dt className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                    {t.modes.bossRush.download}
                  </dt>
                  <dd>
                    <Badge>{t.modes.bossRush.directZipAvailable}</Badge>
                  </dd>
                </div>
              </dl>
            </div>

            <div className="flex flex-col gap-4">
              <h3 className="font-teko uppercase text-2xl leading-none tracking-widest text-bap-pink">
                {t.modes.bossRush.dedicatedMods}
              </h3>
              <ul className="flex flex-col divide-y divide-bap-line border border-bap-line bg-bap-night">
                {bossRushMods.map((mod) => (
                  <li key={mod.id}>
                    <Link
                      to={`/mods/${mod.id}`}
                      className="group flex items-center gap-4 px-5 py-4 transition duration-150 hover:bg-bap-plum"
                    >
                      <span className="h-2.5 w-2.5 shrink-0 bg-bap-pink" />
                      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                        <span className="font-teko uppercase text-xl leading-none text-white group-hover:text-bap-pink">
                          {mod.name}
                        </span>
                        <span className="truncate text-sm text-white/60">
                          {mod.summary}
                        </span>
                      </span>
                      <span
                        aria-hidden
                        className="font-teko text-xl leading-none text-bap-pink"
                      >
                        →
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* Battle Royale bundle */}
      <section
        aria-labelledby="battle-royale-heading"
        className="mx-auto max-w-7xl px-4 py-16 md:px-6"
      >
        <div
          ref={revealBundle.ref}
          className={`flex flex-col gap-6 border border-bap-line bg-bap-plum p-6 transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)] md:p-10 ${revealBundle.className}`}
        >
          <div className="flex flex-col gap-2">
            <span className="font-teko uppercase text-bap-pink tracking-widest text-lg leading-none">
              {t.modes.bundle.eyebrow}
            </span>
            <h2
              id="battle-royale-heading"
              className="font-display uppercase text-3xl text-white md:text-4xl"
            >
              {brBundle.name}
            </h2>
            <p className="font-teko uppercase text-2xl leading-none text-bap-amber">
              &ldquo;{brBundle.notes}&rdquo;
            </p>
          </div>

          <div className="flex flex-wrap gap-1.5">
            <Badge tone="pink">v{brBundle.version}</Badge>
            <Badge>{t.modes.bundle.published(brBundle.published)}</Badge>
            <Badge>{brBundle.sizeDisplay}</Badge>
            <Badge tone="amber">
              {t.modes.bundle.requiresLauncher(brBundle.minLauncherVersion)}
            </Badge>
          </div>

          <p className="max-w-2xl text-white/60 text-sm">
            {t.modes.bundle.text}
          </p>

          <div className="flex flex-wrap items-center gap-4">
            <GradientButton variant="outline" to={`/mods/${BR_UI_MOD_ID}`}>
              {t.modes.bundle.pairWith}
            </GradientButton>
          </div>
        </div>
      </section>

      {/* Version Time Machine */}
      <section
        aria-labelledby="time-machine-heading"
        className="border-t border-bap-line bg-bap-plum/30"
      >
        <div
          ref={revealVersions.ref}
          className={`mx-auto max-w-7xl px-4 py-16 pb-20 md:px-6 ${revealVersions.className}`}
        >
          <SectionHeading
            id="time-machine-heading"
            eyebrow={t.modes.timeMachine.eyebrow}
            title={t.modes.timeMachine.title}
            subtitle={t.modes.timeMachine.subtitle}
          />

          {/* `relative` keeps sr-only (absolutely positioned) table descendants
              inside this scroll container so they can't widen the page. */}
          <div className="relative mt-10 overflow-x-auto border border-bap-line bg-bap-black">
            <table className="w-full min-w-[40rem] text-left text-sm">
              <caption className="sr-only">
                {t.modes.timeMachine.tableCaption}
              </caption>
              <thead>
                <tr className="border-b border-bap-line font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                  <th scope="col" className="px-5 py-3 font-normal">
                    {t.modes.timeMachine.buildHeader}
                  </th>
                  <th scope="col" className="px-5 py-3 font-normal">
                    {t.modes.timeMachine.trackHeader}
                  </th>
                  <th scope="col" className="px-5 py-3 font-normal">
                    {t.modes.timeMachine.releasedHeader}
                  </th>
                  <th scope="col" className="px-5 py-3 font-normal">
                    {t.modes.timeMachine.steamManifestHeader}
                  </th>
                  <th scope="col" className="px-5 py-3 font-normal">
                    <span className="sr-only">
                      {t.modes.timeMachine.badgesHeader}
                    </span>
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-bap-line">
                {VERSIONS.builds.map((build) => (
                  <tr
                    key={build.id}
                    className="transition duration-150 hover:bg-bap-plum/50"
                  >
                    <td className="px-5 py-3 font-teko uppercase text-xl leading-none text-white">
                      {build.gameVersion}
                    </td>
                    <td className="px-5 py-3">
                      <Badge
                        tone={build.track === 'boss-rush' ? 'pink' : 'neutral'}
                      >
                        {build.track}
                      </Badge>
                    </td>
                    <td className="px-5 py-3 text-white/60">
                      {formatDate(build.releaseDateUtc)}
                    </td>
                    <td className="max-w-[10rem] truncate px-5 py-3 text-white/40 md:max-w-none">
                      {build.steamManifestId}
                    </td>
                    <td className="px-5 py-3">
                      <span className="flex flex-wrap gap-1.5">
                        {build.recommended && (
                          <Badge tone="amber">
                            {t.modes.timeMachine.recommended}
                          </Badge>
                        )}
                        {build.directDownload && (
                          <Badge>{t.modes.timeMachine.directZip}</Badge>
                        )}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <p className="mt-4 text-sm text-white/40">
            {t.modes.timeMachine.footer(
              VERSIONS.steamAppId,
              VERSIONS.steamDepotId,
            )}
          </p>

          <div className="mt-10 flex justify-center">
            <GradientButton to="/launcher">
              {t.modes.timeMachine.cta}
            </GradientButton>
          </div>
        </div>
      </section>
    </>
  )
}
