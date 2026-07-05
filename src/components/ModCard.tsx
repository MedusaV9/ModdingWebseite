import { useState } from 'react'
import type { Mod } from '../data/mods'
import Badge from './Badge'

function initials(name: string) {
  return name
    .split(/\s+/)
    .map((word) => word.replace(/[^a-zA-Z0-9]/g, '').charAt(0))
    .filter(Boolean)
    .slice(0, 3)
    .join('')
    .toUpperCase()
}

export default function ModCard({ mod }: { mod: Mod }) {
  const [errorCount, setErrorCount] = useState(0)

  const src = errorCount === 0 ? `/assets/mods/${mod.id}.png` : mod.thumb

  return (
    <article className="group relative flex flex-col bg-bap-plum border border-bap-line transition duration-150 hover:border-bap-pink hover:-translate-y-1">
      <div className="relative aspect-video overflow-hidden bg-gradient-to-br from-bap-red to-bap-plum">
        <div className="absolute inset-0 flex items-center justify-center">
          <span className="font-display text-4xl text-white/30 uppercase">
            {initials(mod.name)}
          </span>
        </div>
        {errorCount < 2 && (
          <img
            src={src}
            alt={mod.name}
            loading="lazy"
            onError={() => setErrorCount((count) => count + 1)}
            className="relative h-full w-full object-cover transition duration-300 group-hover:scale-105"
          />
        )}
        {mod.ribbon === 'host-only' && (
          <Badge tone="amber" className="absolute top-2 left-2">
            HOST-ONLY
          </Badge>
        )}
        {mod.ribbon === 'new' && (
          <Badge tone="pink" className="absolute top-2 left-2">
            NEW
          </Badge>
        )}
      </div>

      <div className="flex flex-1 flex-col gap-3 p-4">
        <h3 className="font-display text-sm uppercase text-white">
          {mod.name}
        </h3>
        <p className="text-white/60 text-sm">{mod.summary}</p>
        <div className="flex flex-wrap gap-1.5">
          {mod.tags.slice(0, 3).map((tag) => (
            <Badge key={tag}>{tag}</Badge>
          ))}
        </div>
        <div className="mt-auto flex items-center justify-between border-t border-bap-line pt-3 font-teko uppercase text-white/40 leading-none">
          <span>v{mod.version}</span>
          <span>by {mod.author}</span>
        </div>
      </div>
    </article>
  )
}
