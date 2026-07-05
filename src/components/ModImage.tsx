import { useState } from 'react'
import type { Mod } from '../data/mods'

function initials(name: string) {
  return name
    .split(/\s+/)
    .map((word) => word.replace(/[^a-zA-Z0-9]/g, '').charAt(0))
    .filter(Boolean)
    .slice(0, 3)
    .join('')
    .toUpperCase()
}

/**
 * Shared mod artwork with a three-step fallback chain:
 * local /assets/mods/<id>.png → remote manifest thumb → initials tile.
 */
export default function ModImage({
  mod,
  className = '',
}: {
  mod: Mod
  className?: string
}) {
  const [errorCount, setErrorCount] = useState(0)

  const src = errorCount === 0 ? `/assets/mods/${mod.id}.png` : mod.thumb

  return (
    <div
      className={`relative overflow-hidden bg-gradient-to-br from-bap-red to-bap-plum ${className}`}
    >
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
    </div>
  )
}
