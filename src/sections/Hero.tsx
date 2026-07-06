import { useEffect, useState } from 'react'
import type { CSSProperties, PointerEvent as ReactPointerEvent } from 'react'
import Badge from '../components/Badge'
import GradientButton from '../components/GradientButton'
import Marquee from '../components/Marquee'
import Emblem from '../components/brand/Emblem'
import Icon from '../components/brand/Icon'
import {
  BangSticker,
  CrosshairSticker,
  GhostSticker,
  SparkSticker,
} from '../components/brand/Sticker'
import useCountUp from '../hooks/useCountUp'
import useReveal from '../hooks/useReveal'
import { LAUNCHER } from '../data/launcher'
import { LINKS } from '../data/links'
import { MODES } from '../data/modes'
import { MODS } from '../data/mods'
import { RADIO } from '../data/radio'

// Numeric values are counted up on scroll; version strings stay static.
const stats: { value: number | string; label: string }[] = [
  { value: MODS.length, label: 'MODS & TOOLS' },
  { value: MODES.length, label: 'GAME TRACKS' },
  { value: RADIO.tracks.length, label: 'RADIO TRACKS' },
  { value: '0.7.2', label: 'MELONLOADER' },
  { value: `v${LAUNCHER.version}`, label: 'NEXUS' },
]

function CountUpValue({ target }: { target: number }) {
  const { ref, value } = useCountUp<HTMLElement>(target)
  return (
    <dd ref={ref} className="text-4xl leading-none text-bap-pink">
      {value}
    </dd>
  )
}

export default function Hero() {
  const reveal = useReveal()

  // Pointer parallax: only active on fine pointers with reduced motion off.
  // When gated off no pointer listeners are attached at all.
  const [parallaxOn, setParallaxOn] = useState(false)
  const [pointer, setPointer] = useState({ x: 0, y: 0 })

  useEffect(() => {
    const finePointer = window.matchMedia('(pointer: fine)')
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)')
    const update = () => {
      const on = finePointer.matches && !reducedMotion.matches
      setParallaxOn(on)
      if (!on) setPointer({ x: 0, y: 0 })
    }
    update()
    finePointer.addEventListener('change', update)
    reducedMotion.addEventListener('change', update)
    return () => {
      finePointer.removeEventListener('change', update)
      reducedMotion.removeEventListener('change', update)
    }
  }, [])

  const handlePointerMove = (event: ReactPointerEvent<HTMLElement>) => {
    const rect = event.currentTarget.getBoundingClientRect()
    setPointer({
      x: (event.clientX - rect.left) / rect.width - 0.5,
      y: (event.clientY - rect.top) / rect.height - 0.5,
    })
  }

  const handlePointerLeave = () => setPointer({ x: 0, y: 0 })

  const layerStyle = (depth: number): CSSProperties | undefined =>
    parallaxOn
      ? {
          transform: `translate(${(pointer.x * depth).toFixed(2)}px, ${(
            pointer.y * depth
          ).toFixed(2)}px)`,
          transition: 'transform 200ms ease-out',
        }
      : undefined

  return (
    <section
      aria-labelledby="hero-heading"
      className="relative flex min-h-[90vh] flex-col overflow-hidden bg-bap-night"
      onPointerMove={parallaxOn ? handlePointerMove : undefined}
      onPointerLeave={parallaxOn ? handlePointerLeave : undefined}
    >
      {/* Layer 0 — backdrop: glows + pink grid + scanlines */}
      <div aria-hidden className="pointer-events-none absolute inset-0">
        <div className="absolute -top-40 left-[calc(50%-17rem)] h-[34rem] w-[34rem] rounded-full bg-bap-pink/15 blur-[120px] [animation:float_6s_ease-in-out_infinite_alternate]" />
        <div className="absolute bottom-0 -right-40 h-[26rem] w-[26rem] rounded-full bg-bap-pink/10 blur-[110px] [animation:float_6s_ease-in-out_-4s_infinite_alternate]" />
        <div className="absolute inset-0 bg-[repeating-linear-gradient(to_right,rgba(255,42,109,0.05)_0,rgba(255,42,109,0.05)_1px,transparent_1px,transparent_64px),repeating-linear-gradient(to_bottom,rgba(255,42,109,0.05)_0,rgba(255,42,109,0.05)_1px,transparent_1px,transparent_64px)]" />
        <div className="absolute inset-0 bg-[repeating-linear-gradient(to_bottom,rgba(255,255,255,0.02)_0,rgba(255,255,255,0.02)_1px,transparent_1px,transparent_3px)]" />
      </div>

      <div className="relative flex flex-1 items-center justify-center px-4 py-20 md:px-6">
        {/* Layer 1 — art: emblem right-of-center + floating stickers */}
        <div aria-hidden className="pointer-events-none absolute inset-0">
          <div className="absolute top-1/2 left-1/2 -translate-y-1/2">
            <div style={layerStyle(14)}>
              <Emblem className="h-72 w-72 opacity-15 md:h-96 md:w-96" />
            </div>
          </div>
          <div className="absolute top-[4%] left-[4%] md:top-[10%] md:left-[13%]">
            <div style={layerStyle(20)}>
              <GhostSticker className="h-16 w-16 [animation:float_5s_ease-in-out_-0.8s_infinite_alternate]" />
            </div>
          </div>
          <div className="absolute top-[8%] right-[6%] md:top-[13%] md:right-[17%]">
            <div style={layerStyle(28)}>
              <SparkSticker className="h-8 w-8 [animation:float_4s_ease-in-out_-2.1s_infinite_alternate]" />
            </div>
          </div>
          <div className="absolute bottom-[3%] left-[6%] md:bottom-[10%] md:left-[17%]">
            <div style={layerStyle(24)}>
              <CrosshairSticker className="h-12 w-12 [animation:float_6s_ease-in-out_-3.4s_infinite_alternate]" />
            </div>
          </div>
          <div className="absolute top-[56%] right-[3%] md:top-[52%] md:right-[9%]">
            <div style={layerStyle(26)}>
              <BangSticker className="h-10 w-10 [animation:float_5s_ease-in-out_-1.6s_infinite_alternate]" />
            </div>
          </div>
        </div>

        <div
          ref={reveal.ref}
          className={`relative flex max-w-4xl flex-col items-center gap-6 text-center ${reveal.className}`}
        >
          <Badge tone="amber">
            COMMUNITY PROJECT — NOT AFFILIATED WITH BAPBAP HQ
          </Badge>

          <h1
            id="hero-heading"
            className="font-display uppercase leading-none text-5xl sm:text-7xl md:text-8xl lg:text-9xl"
          >
            <span className="block text-white">BAPBAP</span>
            {/* 3-stop gradient tiles seamlessly while gradient-pan loops */}
            <span className="block bg-[linear-gradient(90deg,#ff2a6d,#eb204f,#ff2a6d)] bg-clip-text text-transparent [background-size:200%_auto] [animation:gradient-pan_6s_linear_infinite]">
              MODDING
            </span>
          </h1>

          <p className="font-teko uppercase text-2xl leading-none text-white/80">
            COMMUNITY MODS <span className="text-bap-pink">✕</span> CUSTOM
            MODES <span className="text-bap-pink">✕</span> ONE LAUNCHER
          </p>

          <div className="mt-2 flex flex-wrap items-center justify-center gap-4">
            <GradientButton
              size="lg"
              icon={<Icon name="arrow-right" className="h-5 w-5" />}
              className="shadow-hard"
              href={LINKS.discord}
              target="_blank"
              rel="noreferrer"
            >
              JOIN THE DISCORD
            </GradientButton>
            <GradientButton variant="outline" to="/launcher">
              GET THE LAUNCHER
            </GradientButton>
          </div>

          <p className="font-teko uppercase text-white/60 leading-none tracking-wide">
            FOR BAPBAP — THE ROGUELIKE PARTY GAME ON STEAM
          </p>
        </div>
      </div>

      {/* Angled kinetic band — clipped horizontally by the section's overflow-hidden */}
      <div className="relative py-8">
        <div className="w-[110%] -ml-[5%] -rotate-2">
          <Marquee text="READY TO MOD?" speed={22} />
        </div>
      </div>

      {/* Stats strip */}
      <div className="relative border-t-2 border-t-bap-pink border-b border-b-bap-line bg-bap-plum/50">
        <dl className="mx-auto grid max-w-7xl grid-cols-2 gap-x-4 gap-y-6 px-4 py-6 sm:grid-cols-3 md:grid-cols-5 md:px-6">
          {stats.map((stat) => (
            <div
              key={stat.label}
              className="flex flex-col items-center gap-1 text-center font-teko uppercase"
            >
              {typeof stat.value === 'number' ? (
                <CountUpValue target={stat.value} />
              ) : (
                <dd className="text-4xl leading-none text-bap-pink">
                  {stat.value}
                </dd>
              )}
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
