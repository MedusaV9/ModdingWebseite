import Badge from '../components/Badge'
import GradientButton from '../components/GradientButton'
import SectionHeading from '../components/SectionHeading'
import usePageTitle from '../hooks/usePageTitle'
import useReveal from '../hooks/useReveal'
import { LINKS } from '../data/links'
import { RADIO, type RadioTrack } from '../data/radio'

const GROUP_ORDER = [
  'Lobby',
  'Rigtown',
  'Stage',
  'Dimension',
  'Loop',
  'Tutorial',
  'Misc',
]

function formatDuration(ms: number) {
  const totalSeconds = Math.floor(ms / 1000)
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60
  return `${minutes}:${String(seconds).padStart(2, '0')}`
}

const totalMs = RADIO.tracks.reduce((sum, track) => sum + track.durationMs, 0)

const stats = [
  { value: String(RADIO.tracks.length), label: 'TRACKS' },
  { value: String(GROUP_ORDER.length), label: 'SCENES' },
  { value: formatDuration(totalMs), label: 'RUNTIME' },
]

const grouped = GROUP_ORDER.map((group) => ({
  group,
  tracks: RADIO.tracks
    .map((track, index) => ({ track, number: index + 1 }))
    .filter(({ track }) => track.group === group),
})).filter(({ tracks }) => tracks.length > 0)

function TrackRow({ track, number }: { track: RadioTrack; number: number }) {
  return (
    <li className="flex items-center gap-3 px-5 py-3 sm:gap-4">
      <span className="w-7 shrink-0 font-teko text-lg leading-none text-white/40">
        {String(number).padStart(2, '0')}
      </span>
      <span className="min-w-0 flex-1 truncate font-teko uppercase text-xl leading-none text-white">
        {track.title}
      </span>
      <Badge className="hidden sm:inline-flex">{track.group}</Badge>
      <span className="shrink-0 text-right font-teko text-lg leading-none text-white/60 tabular-nums">
        {formatDuration(track.durationMs)}
      </span>
    </li>
  )
}

export default function RadioPage() {
  usePageTitle('Radio')

  const revealHeader = useReveal()
  const revealTracks = useReveal()
  const revealNote = useReveal()

  return (
    <>
      {/* Header + stats strip */}
      <section
        aria-labelledby="radio-heading"
        className="mx-auto max-w-7xl px-4 pt-20 md:px-6"
      >
        <div ref={revealHeader.ref} className={revealHeader.className}>
          <SectionHeading
            id="radio-heading"
            eyebrow="OFFLINE SOUNDTRACK STATION"
            title="BAPBAP RADIO"
            subtitle="The 15 official BAPBAP soundtrack pieces bundled with the BAPBAP Nexus launcher radio — from the chill lobby loops to the Dimension combat themes."
          />

          <div className="mt-10 border-y border-bap-line bg-bap-plum/50">
            <dl className="grid grid-cols-1 gap-x-4 gap-y-6 px-4 py-6 sm:grid-cols-3 md:px-6">
              {stats.map((stat) => (
                <div
                  key={stat.label}
                  className="flex flex-col items-center gap-1 text-center font-teko uppercase"
                >
                  <dd className="text-4xl leading-none text-bap-pink">
                    {stat.value}
                  </dd>
                  <dt className="text-sm leading-none tracking-widest text-white/60">
                    {stat.label}
                  </dt>
                </div>
              ))}
            </dl>
          </div>
        </div>
      </section>

      {/* Track list grouped by scene */}
      <section
        aria-label="Radio track list"
        className="mx-auto max-w-7xl px-4 py-16 md:px-6"
      >
        <div
          ref={revealTracks.ref}
          className={`grid grid-cols-1 gap-10 lg:grid-cols-2 ${revealTracks.className}`}
        >
          {grouped.map(({ group, tracks }) => (
            <div key={group} className="flex flex-col gap-3">
              <h2 className="font-teko uppercase text-2xl leading-none tracking-widest text-bap-pink">
                {group}
              </h2>
              <div className="flex flex-col border border-bap-line bg-bap-black">
                <div className="flex items-center justify-between border-b border-bap-line px-5 py-3">
                  <span className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                    {tracks.length} TRACK{tracks.length === 1 ? '' : 'S'}
                  </span>
                  <span className="flex gap-1.5">
                    <span className="h-2.5 w-2.5 rounded-full bg-bap-red" />
                    <span className="h-2.5 w-2.5 rounded-full bg-bap-amber" />
                    <span className="h-2.5 w-2.5 rounded-full bg-bap-pink" />
                  </span>
                </div>
                <ul className="flex flex-col divide-y divide-bap-line">
                  {tracks.map(({ track, number }) => (
                    <TrackRow key={track.id} track={track} number={number} />
                  ))}
                </ul>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Listen in the launcher */}
      <section
        aria-labelledby="radio-listen-heading"
        className="mx-auto max-w-7xl px-4 pb-20 md:px-6"
      >
        <div
          ref={revealNote.ref}
          className={`flex flex-col gap-6 border border-bap-line bg-bap-plum p-6 transition duration-150 hover:border-bap-pink md:p-10 ${revealNote.className}`}
        >
          <div className="flex flex-col gap-2">
            <h2
              id="radio-listen-heading"
              className="font-display uppercase text-2xl text-white md:text-3xl"
            >
              LISTEN IN THE LAUNCHER
            </h2>
            <p className="max-w-2xl text-white/60">
              This site doesn&apos;t ship the audio files — the full station
              plays offline inside the BAPBAP Nexus launcher. The track list
              lives in the open launcher manifest on GitHub.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-4">
            <GradientButton to="/launcher">GET THE LAUNCHER</GradientButton>
            <GradientButton
              variant="outline"
              href={LINKS.github}
              target="_blank"
              rel="noreferrer"
            >
              OPEN MANIFEST ON GITHUB
            </GradientButton>
          </div>
        </div>
      </section>
    </>
  )
}
