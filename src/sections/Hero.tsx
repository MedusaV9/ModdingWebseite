import Badge from '../components/Badge'
import GradientButton from '../components/GradientButton'
import useReveal from '../hooks/useReveal'
import { LINKS } from '../data/links'

const stats = [
  { value: '12', label: 'MODS & TOOLS' },
  { value: '3', label: 'GAME TRACKS' },
  { value: '16', label: 'RADIO TRACKS' },
  { value: '0.7.2', label: 'MELONLOADER' },
  { value: 'v4.0.4', label: 'NEXUS' },
]

export default function Hero() {
  const reveal = useReveal()

  return (
    <section
      id="top"
      aria-labelledby="hero-heading"
      className="relative flex min-h-[90vh] flex-col bg-bap-night"
    >
      {/* Decorative background: glows + grid */}
      <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
        <div className="absolute -top-40 left-[calc(50%-17rem)] h-[34rem] w-[34rem] rounded-full bg-bap-pink/15 blur-[120px] [animation:float_6s_ease-in-out_infinite_alternate]" />
        <div className="absolute top-1/3 -left-40 h-[28rem] w-[28rem] rounded-full bg-bap-red/10 blur-[110px] [animation:float_6s_ease-in-out_-2s_infinite_alternate]" />
        <div className="absolute bottom-0 -right-40 h-[26rem] w-[26rem] rounded-full bg-bap-pink/10 blur-[110px] [animation:float_6s_ease-in-out_-4s_infinite_alternate]" />
        <div className="absolute inset-0 bg-[repeating-linear-gradient(to_right,rgba(255,42,109,0.05)_0,rgba(255,42,109,0.05)_1px,transparent_1px,transparent_64px),repeating-linear-gradient(to_bottom,rgba(255,42,109,0.05)_0,rgba(255,42,109,0.05)_1px,transparent_1px,transparent_64px)]" />
      </div>

      <div className="relative flex flex-1 items-center justify-center px-4 py-20 md:px-6">
        <div
          ref={reveal.ref}
          className={`flex max-w-4xl flex-col items-center gap-6 text-center ${reveal.className}`}
        >
          <Badge tone="amber">
            COMMUNITY PROJECT — NOT AFFILIATED WITH BAPBAP HQ
          </Badge>

          <h1
            id="hero-heading"
            className="font-display uppercase leading-none text-5xl sm:text-7xl md:text-8xl lg:text-9xl"
          >
            <span className="block text-white">BAPBAP</span>
            <span className="block bg-gradient-to-r from-[#eb204f] to-[#ff2a6d] bg-clip-text text-transparent">
              MODDING
            </span>
          </h1>

          <p className="font-teko uppercase text-2xl leading-none text-white/80">
            COMMUNITY MODS <span className="text-bap-pink">✕</span> CUSTOM
            MODES <span className="text-bap-pink">✕</span> ONE LAUNCHER
          </p>

          <div className="mt-2 flex flex-wrap items-center justify-center gap-4">
            <GradientButton href={LINKS.discord} target="_blank" rel="noreferrer">
              JOIN THE DISCORD
            </GradientButton>
            <GradientButton variant="outline" href="#launcher">
              GET THE LAUNCHER
            </GradientButton>
          </div>

          <p className="font-teko uppercase text-white/60 leading-none tracking-wide">
            FOR BAPBAP — THE ROGUELIKE PARTY GAME ON STEAM
          </p>
        </div>
      </div>

      {/* Stats strip */}
      <div className="relative border-y border-bap-line bg-bap-plum/50">
        <dl className="mx-auto grid max-w-7xl grid-cols-2 gap-x-4 gap-y-6 px-4 py-6 sm:grid-cols-3 md:grid-cols-5 md:px-6">
          {stats.map((stat) => (
            <div key={stat.label} className="flex flex-col items-center gap-1 text-center font-teko uppercase">
              <dd className="text-4xl leading-none text-bap-pink">{stat.value}</dd>
              <dt className="text-sm leading-none tracking-widest text-white/60">
                {stat.label}
              </dt>
            </div>
          ))}
        </dl>
      </div>
    </section>
  )
}
