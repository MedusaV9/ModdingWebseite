import Badge from '../components/Badge'
import SectionHeading from '../components/SectionHeading'
import useReveal from '../hooks/useReveal'
import { MODES } from '../data/modes'

const headerArt: Record<string, string> = {
  'boss-rush':
    'bg-[repeating-linear-gradient(135deg,#eb204f_0,#eb204f_14px,#ff2a6d_14px,#ff2a6d_28px)]',
  'battle-royale': 'bg-gradient-to-br from-bap-amber to-bap-amber2',
  'time-machine':
    'bg-bap-plum bg-[repeating-linear-gradient(to_bottom,rgba(255,42,109,0.3)_0,rgba(255,42,109,0.3)_1px,transparent_1px,transparent_7px)]',
}

export default function GameModes() {
  const reveal = useReveal()

  return (
    <section
      id="modes"
      aria-labelledby="modes-heading"
      className="border-y border-bap-line bg-bap-plum/30"
    >
      <div
        ref={reveal.ref}
        className={`mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28 ${reveal.className}`}
      >
        <SectionHeading
          id="modes-heading"
          eyebrow="MORE WAYS TO PLAY"
          title="GAME MODES & TRACKS"
        />

        <div className="mt-12 grid grid-cols-1 gap-6 lg:grid-cols-3">
          {MODES.map((mode) => (
            <article
              key={mode.id}
              className="flex flex-col border border-bap-line bg-bap-night transition duration-150 hover:border-bap-pink"
            >
              <div className={`h-24 ${headerArt[mode.id] ?? ''}`} />
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
  )
}
