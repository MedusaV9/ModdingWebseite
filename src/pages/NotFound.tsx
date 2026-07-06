import { useNavigate } from 'react-router-dom'
import GradientButton from '../components/GradientButton'
import Icon from '../components/brand/Icon'
import usePageMeta from '../hooks/usePageMeta'
import { randomModId } from '../lib/randomMod'

export default function NotFound() {
  usePageMeta('404', 'This page got BAPPED — back to the mods.')

  const navigate = useNavigate()

  return (
    <section
      aria-labelledby="not-found-heading"
      className="mx-auto flex max-w-7xl flex-col items-center gap-6 px-4 py-24 text-center md:px-6 md:py-36"
    >
      <h1
        id="not-found-heading"
        className="font-display text-[7rem] leading-none text-transparent sm:text-[10rem] md:text-[13rem] [animation:glitch_3s_steps(1)_infinite]"
        style={{ WebkitTextStroke: '2px rgba(255,42,109,0.6)' }}
      >
        404
      </h1>
      <p className="font-teko uppercase text-3xl leading-none text-white/80 md:text-4xl">
        THIS PAGE GOT <span className="text-bap-pink">BAPPED</span>
      </p>
      <p className="font-teko uppercase text-xl leading-none text-white/50">
        TIP: PRESS{' '}
        <kbd className="border border-bap-line bg-bap-plum px-1.5 pt-1 pb-0.5 text-white/80">
          /
        </kbd>{' '}
        TO SEARCH THE SITE
      </p>
      <div className="mt-2 flex flex-wrap items-center justify-center gap-4">
        <GradientButton to="/">BACK TO HOME</GradientButton>
        <GradientButton variant="outline" to="/mods">
          BROWSE THE MODS
        </GradientButton>
        <GradientButton
          variant="outline"
          to="/mods"
          icon={<Icon name="shuffle" className="h-5 w-5" />}
          onClick={(event) => {
            // Pick the random mod at click time (same pattern as the mods
            // page); /mods stays as the no-JS fallback href.
            event.preventDefault()
            navigate(`/mods/${randomModId()}`)
          }}
        >
          SURPRISE ME
        </GradientButton>
      </div>
    </section>
  )
}
