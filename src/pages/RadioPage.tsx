import { useState } from 'react'
import Badge from '../components/Badge'
import GradientButton from '../components/GradientButton'
import RadioPlayer, { EqualizerBars } from '../components/RadioPlayer'
import SectionHeading from '../components/SectionHeading'
import usePageMeta from '../hooks/usePageMeta'
import useReveal from '../hooks/useReveal'
import { useI18n } from '../i18n/context'
import { LINKS } from '../data/links'
import { RADIO, type RadioTrack } from '../data/radio'
import { formatDuration } from '../lib/formatDuration'

const GROUP_ORDER = [
  'Lobby',
  'Rigtown',
  'Stage',
  'Dimension',
  'Loop',
  'Tutorial',
  'Misc',
]

const totalMs = RADIO.tracks.reduce((sum, track) => sum + track.durationMs, 0)

// Labels come from the dict (t.radio.stats, same order) inside the component.
const statValues = [
  String(RADIO.tracks.length),
  String(GROUP_ORDER.length),
  formatDuration(totalMs),
]

const grouped = GROUP_ORDER.map((group) => ({
  group,
  tracks: RADIO.tracks
    .map((track, index) => ({ track, number: index + 1 }))
    .filter(({ track }) => track.group === group),
})).filter(({ tracks }) => tracks.length > 0)

function TrackRow({
  track,
  number,
  active,
  playing,
  onSelect,
}: {
  track: RadioTrack
  number: number
  active: boolean
  playing: boolean
  onSelect: () => void
}) {
  const { t } = useI18n()
  return (
    <li>
      <button
        type="button"
        onClick={onSelect}
        aria-current={active ? 'true' : undefined}
        aria-label={t.radio.playTrack(
          track.title,
          formatDuration(track.durationMs),
        )}
        className="flex w-full items-center gap-3 px-5 py-3 text-left transition-colors hover:bg-bap-pink/5 cursor-pointer sm:gap-4"
      >
        <span className="w-7 shrink-0 font-teko text-lg leading-none text-white/40">
          {active ? (
            <EqualizerBars
              playing={playing}
              heights={[10, 14, 7]}
              barClassName="w-1"
              className="h-3.5"
            />
          ) : (
            String(number).padStart(2, '0')
          )}
        </span>
        <span
          className={`min-w-0 flex-1 truncate font-teko uppercase text-xl leading-none ${
            active ? 'text-bap-pink' : 'text-white'
          }`}
        >
          {track.title}
        </span>
        <Badge className="hidden sm:inline-flex">{track.group}</Badge>
        <span className="shrink-0 text-right font-teko text-lg leading-none text-white/60 tabular-nums">
          {formatDuration(track.durationMs)}
        </span>
      </button>
    </li>
  )
}

export default function RadioPage() {
  const { t } = useI18n()
  usePageMeta(t.meta.radio.title, t.meta.radio.description)

  const stats = t.radio.stats.map((label, index) => ({
    label,
    value: statValues[index],
  }))

  const revealHeader = useReveal()
  const revealTracks = useReveal()
  const revealNote = useReveal()

  const [currentIndex, setCurrentIndex] = useState(0)
  const [playing, setPlaying] = useState(false)

  function playTrack(index: number) {
    setCurrentIndex(index)
    setPlaying(true)
  }

  return (
    <>
      {/* Header + stats strip */}
      <section
        aria-labelledby="radio-heading"
        className="mx-auto max-w-7xl px-4 pt-20 md:px-6 md:pt-28"
      >
        <div ref={revealHeader.ref} className={revealHeader.className}>
          <SectionHeading
            id="radio-heading"
            eyebrow={t.radio.eyebrow}
            title={t.radio.title}
            subtitle={t.radio.subtitle}
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

        {/* Visualizer deck — no <audio>: the site ships no audio files. */}
        <div className="mt-12">
          <RadioPlayer
            currentIndex={currentIndex}
            playing={playing}
            onPlayingChange={setPlaying}
            onTrackChange={setCurrentIndex}
          />
        </div>
      </section>

      {/* Track list grouped by scene */}
      <section
        aria-label={t.radio.trackListLabel}
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
                    {t.radio.trackCount(tracks.length)}
                  </span>
                  <span className="flex gap-1.5">
                    <span className="h-2.5 w-2.5 rounded-full bg-bap-red" />
                    <span className="h-2.5 w-2.5 rounded-full bg-bap-amber" />
                    <span className="h-2.5 w-2.5 rounded-full bg-bap-pink" />
                  </span>
                </div>
                <ul className="flex flex-col divide-y divide-bap-line">
                  {tracks.map(({ track, number }) => (
                    <TrackRow
                      key={track.id}
                      track={track}
                      number={number}
                      active={currentIndex === number - 1}
                      playing={playing}
                      onSelect={() => playTrack(number - 1)}
                    />
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
          className={`flex flex-col gap-6 border border-bap-line bg-bap-plum p-6 transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)] md:p-10 ${revealNote.className}`}
        >
          <div className="flex flex-col gap-2">
            <h2
              id="radio-listen-heading"
              className="font-display uppercase text-2xl text-white md:text-3xl"
            >
              {t.radio.listen.title}
            </h2>
            <p className="max-w-2xl text-white/60">{t.radio.listen.text}</p>
          </div>
          <div className="flex flex-wrap items-center gap-4">
            <GradientButton to="/launcher">
              {t.radio.listen.getLauncher}
            </GradientButton>
            <GradientButton
              variant="outline"
              href={LINKS.github}
              target="_blank"
              rel="noreferrer"
            >
              {t.radio.listen.openManifest}
            </GradientButton>
          </div>
        </div>
      </section>
    </>
  )
}
