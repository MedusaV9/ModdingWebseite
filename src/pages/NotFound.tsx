import GradientButton from '../components/GradientButton'
import usePageTitle from '../hooks/usePageTitle'

export default function NotFound() {
  usePageTitle('404')

  return (
    <section
      aria-labelledby="not-found-heading"
      className="mx-auto flex max-w-7xl flex-col items-center gap-6 px-4 py-24 text-center md:px-6 md:py-36"
    >
      <h1
        id="not-found-heading"
        className="font-display text-[7rem] leading-none text-transparent sm:text-[10rem] md:text-[13rem]"
        style={{ WebkitTextStroke: '2px rgba(255,42,109,0.6)' }}
      >
        404
      </h1>
      <p className="font-teko uppercase text-3xl leading-none text-white/80 md:text-4xl">
        THIS PAGE GOT <span className="text-bap-pink">BAPPED</span>
      </p>
      <div className="mt-2 flex flex-wrap items-center justify-center gap-4">
        <GradientButton to="/">BACK TO HOME</GradientButton>
        <GradientButton variant="outline" to="/mods">
          BROWSE THE MODS
        </GradientButton>
      </div>
    </section>
  )
}
