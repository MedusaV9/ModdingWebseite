import { useState } from 'react'
import GradientButton from '../components/GradientButton'
import ModCard from '../components/ModCard'
import SectionHeading from '../components/SectionHeading'
import useReveal from '../hooks/useReveal'
import { LINKS } from '../data/links'
import { MODS } from '../data/mods'
import type { Mod } from '../data/mods'

type Filter = 'all' | 'mods' | 'tools' | 'boss-rush'

const filters: { id: Filter; label: string; match: (mod: Mod) => boolean }[] = [
  { id: 'all', label: 'ALL', match: () => true },
  { id: 'mods', label: 'MODS', match: (mod) => mod.type === 'mod' },
  { id: 'tools', label: 'TOOLS', match: (mod) => mod.type === 'tool' },
  {
    id: 'boss-rush',
    label: 'BOSS RUSH',
    match: (mod) => mod.track === 'boss-rush',
  },
]

export default function Mods() {
  const [active, setActive] = useState<Filter>('all')
  const reveal = useReveal()

  const activeFilter = filters.find((filter) => filter.id === active) ?? filters[0]
  const visible = MODS.filter(activeFilter.match)

  return (
    <section
      id="mods"
      aria-labelledby="mods-heading"
      className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28"
    >
      <div ref={reveal.ref} className={reveal.className}>
        <SectionHeading
          id="mods-heading"
          eyebrow="BAPHUB CATALOG"
          title="THE MODS"
          subtitle="Real community mods, installable in one click through the BAPBAP Nexus launcher."
        />

        <div className="mt-8 flex flex-wrap gap-3">
          {filters.map((filter) => (
            <button
              key={filter.id}
              type="button"
              onClick={() => setActive(filter.id)}
              className={`font-teko uppercase text-lg leading-none tracking-wide pt-[11px] px-4 pb-1.5 transition cursor-pointer ${
                active === filter.id
                  ? 'text-white bg-[linear-gradient(to_left,#eb204f,#ff2a6d)]'
                  : 'border border-bap-line text-white/60 hover:text-bap-pink'
              }`}
            >
              {filter.label}
            </button>
          ))}
        </div>

        <div className="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {visible.map((mod) => (
            <ModCard key={mod.id} mod={mod} />
          ))}
        </div>

        <div className="mt-12 flex flex-col items-center gap-4 text-center">
          <p className="text-white/60 text-sm">
            Every package is defined in the open BAPHub manifest — inspect it,
            fork it, or submit your own mod.
          </p>
          <GradientButton
            variant="outline"
            href={LINKS.github}
            target="_blank"
            rel="noreferrer"
          >
            BROWSE THE BAPHUB SOURCE
          </GradientButton>
        </div>
      </div>
    </section>
  )
}
