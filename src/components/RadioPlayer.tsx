import { useEffect, useState } from 'react'
import type { CSSProperties } from 'react'
import Badge from './Badge'
import Icon from './brand/Icon'
import { RADIO } from '../data/radio'
import { formatDuration } from '../lib/formatDuration'

/**
 * Shared animated equalizer bars (also used inline in the track list).
 * Negative delays freeze each paused bar at a different phase, so a stopped
 * deck still reads as a static waveform.
 */
export function EqualizerBars({
  playing,
  heights,
  barClassName = 'w-2',
  className = '',
}: {
  playing: boolean
  heights: number[]
  barClassName?: string
  className?: string
}) {
  return (
    <span className={`flex items-end gap-1 ${className}`} aria-hidden="true">
      {heights.map((height, index) => (
        <span
          key={index}
          className={`${barClassName} bg-bap-pink [animation:equalizer_.9s_ease-in-out_infinite_alternate] ${
            playing ? '' : '[animation-play-state:paused]'
          }`}
          style={{ height, animationDelay: `${index * -150}ms` }}
        />
      ))}
    </span>
  )
}

const DECK_BAR_HEIGHTS = [16, 24, 12, 20, 8]

type RadioPlayerProps = {
  currentIndex: number
  playing: boolean
  onPlayingChange: (playing: boolean) => void
  onTrackChange: (index: number) => void
}

/**
 * Soundtrack VISUALIZER deck — deliberately no <audio> element: the site
 * ships no audio files, full playback lives in the launcher.
 */
export default function RadioPlayer({
  currentIndex,
  playing,
  onPlayingChange,
  onTrackChange,
}: RadioPlayerProps) {
  const tracks = RADIO.tracks
  const track = tracks[currentIndex]
  const [positionMs, setPositionMs] = useState(0)

  // New track (row click / skip / auto-advance) restarts the readout.
  // Reset during render (not in an effect) so the auto-advance effect below
  // never sees the previous track's large position against a shorter track.
  const [lastIndex, setLastIndex] = useState(currentIndex)
  if (lastIndex !== currentIndex) {
    setLastIndex(currentIndex)
    setPositionMs(0)
  }

  // The timer is functional (drives readout + auto-advance) so it is NOT
  // gated behind prefers-reduced-motion — only the bar animation is (CSS).
  useEffect(() => {
    if (!playing) return
    const id = window.setInterval(() => {
      setPositionMs((position) => position + 250)
    }, 250)
    return () => window.clearInterval(id)
  }, [playing, currentIndex])

  // Track finished while playing: wrap to the next one and keep playing.
  useEffect(() => {
    if (playing && positionMs >= track.durationMs) {
      onTrackChange((currentIndex + 1) % tracks.length)
    }
  }, [playing, positionMs, track.durationMs, currentIndex, tracks.length, onTrackChange])

  const shownMs = Math.min(positionMs, track.durationMs)
  const fillPercent = (shownMs / track.durationMs) * 100
  const timeText = `${formatDuration(shownMs)} of ${formatDuration(track.durationMs)}`

  return (
    <div className="shadow-hard relative border-2 border-bap-pink bg-bap-black p-6">
      <Badge tone="amber" className="absolute -top-3 right-4">
        VISUALIZER — FULL AUDIO SHIPS IN THE LAUNCHER
      </Badge>

      <div className="flex flex-col gap-6 sm:flex-row sm:items-center">
        <EqualizerBars
          playing={playing}
          heights={DECK_BAR_HEIGHTS}
          className="h-6 shrink-0"
        />

        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <div className="flex flex-wrap items-center gap-3">
            <span className="truncate font-teko uppercase text-2xl leading-none text-white">
              {track.title}
            </span>
            <Badge>{track.group}</Badge>
          </div>
          <span className="font-teko text-lg leading-none text-white/60 tabular-nums">
            {formatDuration(shownMs)} / {formatDuration(track.durationMs)}
          </span>
        </div>

        <div className="flex shrink-0 items-center gap-3">
          <button
            type="button"
            aria-label="Previous track"
            onClick={() =>
              onTrackChange((currentIndex - 1 + tracks.length) % tracks.length)
            }
            className="flex h-10 w-10 items-center justify-center border border-bap-line text-white/80 transition-colors hover:border-bap-pink hover:text-bap-pink cursor-pointer"
          >
            <Icon name="skip-prev" className="h-5 w-5" />
          </button>
          <button
            type="button"
            aria-label={playing ? 'Pause' : 'Play'}
            onClick={() => onPlayingChange(!playing)}
            className="flex h-14 w-14 items-center justify-center bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] text-white transition duration-150 hover:brightness-110 cursor-pointer"
          >
            <Icon name={playing ? 'pause' : 'play'} className="h-7 w-7" />
          </button>
          <button
            type="button"
            aria-label="Next track"
            onClick={() => onTrackChange((currentIndex + 1) % tracks.length)}
            className="flex h-10 w-10 items-center justify-center border border-bap-line text-white/80 transition-colors hover:border-bap-pink hover:text-bap-pink cursor-pointer"
          >
            <Icon name="skip-next" className="h-5 w-5" />
          </button>
        </div>
      </div>

      <input
        type="range"
        min={0}
        max={track.durationMs}
        step={1000}
        value={shownMs}
        onChange={(event) => setPositionMs(Number(event.target.value))}
        aria-label="Seek position"
        aria-valuetext={timeText}
        className="radio-scrubber mt-6"
        style={{ '--scrub-fill': `${fillPercent}%` } as CSSProperties}
      />
    </div>
  )
}
