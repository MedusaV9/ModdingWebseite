import { useNavigate } from 'react-router-dom'
import GradientButton from '../components/GradientButton'
import Icon from '../components/brand/Icon'
import usePageMeta from '../hooks/usePageMeta'
import { useI18n } from '../i18n/context'
import { randomModId } from '../lib/randomMod'

export default function NotFound() {
  const { t } = useI18n()
  usePageMeta(t.meta.notFound.title, t.meta.notFound.description)

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
        {t.notFound.gotBappedPrefix}{' '}
        <span className="text-bap-pink">{t.notFound.gotBappedHighlight}</span>
      </p>
      <p className="font-teko uppercase text-xl leading-none text-white/50">
        {t.notFound.tipBefore}{' '}
        <kbd className="border border-bap-line bg-bap-plum px-1.5 pt-1 pb-0.5 text-white/80">
          /
        </kbd>{' '}
        {t.notFound.tipAfter}
      </p>
      <div className="mt-2 flex flex-wrap items-center justify-center gap-4">
        <GradientButton to="/">{t.notFound.backHome}</GradientButton>
        <GradientButton variant="outline" to="/mods">
          {t.notFound.browseMods}
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
          {t.notFound.surpriseMe}
        </GradientButton>
      </div>
    </section>
  )
}
