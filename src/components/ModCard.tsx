import { Link } from 'react-router-dom'
import type { Mod } from '../data/mods'
import Badge from './Badge'
import ModImage from './ModImage'

export default function ModCard({ mod }: { mod: Mod }) {
  return (
    <Link
      to={`/mods/${mod.id}`}
      className="group relative flex h-full flex-col bg-bap-plum border border-bap-line transition duration-150 hover:border-bap-pink hover:-translate-y-1 hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-bap-pink"
    >
      <article className="flex flex-1 flex-col">
        <div className="relative">
          <ModImage mod={mod} className="aspect-video" />
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
    </Link>
  )
}
