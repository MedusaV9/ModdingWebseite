import { Link } from 'react-router-dom'
import Badge from '../components/Badge'
import GradientButton from '../components/GradientButton'
import ModeArt from '../components/ModeArt'
import SectionHeading from '../components/SectionHeading'
import usePageMeta from '../hooks/usePageMeta'
import useReveal from '../hooks/useReveal'
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
  usePageMeta(
    'Game Modes',
    'Boss Rush, the Battle Royale Playtest and the Version Time Machine — every extra way to play BAPBAP, kept alive by the launcher.',
  )

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
            eyebrow="MORE WAYS TO PLAY"
            title="GAME MODES & TRACKS"
            subtitle="Beyond the standard game, the launcher keeps whole game modes and archived builds alive — all installable in one click."
          />

          <div className="mt-12 grid grid-cols-1 gap-6 lg:grid-cols-3">
            {MODES.map((mode) => (
              <article
                key={mode.id}
                className="flex flex-col border border-bap-line bg-bap-night transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)]"
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
                eyebrow="DEDICATED GAME TRACK"
                title="BOSS RUSH"
                subtitle="Boss Rush isn't a mod — it's a dedicated branch of the game, preserved as its own track in the launcher."
              />
              <dl className="flex flex-col gap-3 border border-bap-line bg-bap-night p-6 text-sm">
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <dt className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                    BRANCH SNAPSHOT
                  </dt>
                  <dd className="font-teko uppercase text-lg leading-none text-white">
                    {bossRushBuild ? formatDate(bossRushBuild.releaseDateUtc) : ''}
                  </dd>
                </div>
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <dt className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                    STEAM MANIFEST
                  </dt>
                  <dd className="break-all text-white/40">
                    {bossRushBuild?.steamManifestId}
                  </dd>
                </div>
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <dt className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                    DOWNLOAD
                  </dt>
                  <dd>
                    <Badge>DIRECT ZIP AVAILABLE</Badge>
                  </dd>
                </div>
              </dl>
            </div>

            <div className="flex flex-col gap-4">
              <h3 className="font-teko uppercase text-2xl leading-none tracking-widest text-bap-pink">
                4 DEDICATED MODS
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
              GAME MODE BUNDLE
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
            <Badge>PUBLISHED {brBundle.published}</Badge>
            <Badge>{brBundle.sizeDisplay}</Badge>
            <Badge tone="amber">
              REQUIRES LAUNCHER ≥ {brBundle.minLauncherVersion}
            </Badge>
          </div>

          <p className="max-w-2xl text-white/60 text-sm">
            One click in the launcher restores the whole Battle Royale mode.
            Pair it with the classic BR UI mod for the full nostalgia hit.
          </p>

          <div className="flex flex-wrap items-center gap-4">
            <GradientButton variant="outline" to={`/mods/${BR_UI_MOD_ID}`}>
              PAIR WITH: BR UI (OLD BUT GOLD)
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
            eyebrow="PLAY ANY BUILD"
            title="VERSION TIME MACHINE"
            subtitle="Every archived official build the launcher can install — hop back in time for legacy strats, comparisons and preservation."
          />

          {/* `relative` keeps sr-only (absolutely positioned) table descendants
              inside this scroll container so they can't widen the page. */}
          <div className="relative mt-10 overflow-x-auto border border-bap-line bg-bap-black">
            <table className="w-full min-w-[40rem] text-left text-sm">
              <caption className="sr-only">
                Archived BAPBAP builds available in the launcher Version Time
                Machine
              </caption>
              <thead>
                <tr className="border-b border-bap-line font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                  <th scope="col" className="px-5 py-3 font-normal">
                    BUILD
                  </th>
                  <th scope="col" className="px-5 py-3 font-normal">
                    TRACK
                  </th>
                  <th scope="col" className="px-5 py-3 font-normal">
                    RELEASED
                  </th>
                  <th scope="col" className="px-5 py-3 font-normal">
                    STEAM MANIFEST
                  </th>
                  <th scope="col" className="px-5 py-3 font-normal">
                    <span className="sr-only">Badges</span>
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
                          <Badge tone="amber">RECOMMENDED</Badge>
                        )}
                        {build.directDownload && <Badge>DIRECT ZIP</Badge>}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <p className="mt-4 text-sm text-white/40">
            Steam App ID {VERSIONS.steamAppId} · Depot {VERSIONS.steamDepotId} ·
            downloads are SHA-256 verified.
          </p>

          <div className="mt-10 flex justify-center">
            <GradientButton to="/launcher">
              GET THE LAUNCHER TO SWITCH BUILDS
            </GradientButton>
          </div>
        </div>
      </section>
    </>
  )
}
